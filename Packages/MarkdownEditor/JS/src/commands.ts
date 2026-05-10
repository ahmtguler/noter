// Translates Swift bridge commands into CodeMirror state edits. Each command
// works with or without a selection: empty-selection actions either insert
// markers around the caret or toggle the current line's prefix; range actions
// wrap or toggle every covered line.

import { EditorView } from "@codemirror/view";
import { EditorSelection, ChangeSpec } from "@codemirror/state";

interface InlineWrap {
    prefix: string;
    suffix: string;
    /// Single-character markers (`*`, `_`) refuse to false-match the inner
    /// edge of doubled markers (`**`, `__`) so styles stack instead of
    /// unwrapping each other.
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

export type PostFn = (msg: object) => void;

export function applyCommand(
    view: EditorView,
    command: string,
    arg: string | null,
    post: PostFn
) {
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
        requestLinkPopover(view, post);
        return;
    }
    if (command === "linkApply") {
        applyLinkPayload(view, arg);
        return;
    }
    if (command === "linkRemove") {
        removeLinkPayload(view, arg);
        return;
    }
    if (command === "codeBlock") {
        applyCodeBlock(view);
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

    // Selection covers wrap markers themselves — strip them.
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

    // Selection wrapped by surrounding markers — strip them.
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

    // Empty selection inside an existing wrap — unwrap.
    if (range.empty) {
        const surrounding = findEnclosingWrap(
            doc.toString(),
            range.from,
            prefix,
            suffix,
            !!singleCharMarker
        );
        if (surrounding) {
            const inner = doc.sliceString(surrounding.openEnd, surrounding.closeStart);
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
        // No surrounding wrap: insert markers, place caret between them.
        view.dispatch({
            changes: { from: range.from, to: range.to, insert: prefix + suffix },
            selection: EditorSelection.single(range.from + prefix.length),
            scrollIntoView: true,
        });
        return;
    }

    // Default: wrap selection.
    const insert = prefix + sliced + suffix;
    view.dispatch({
        changes: { from: range.from, to: range.to, insert },
        selection: EditorSelection.single(
            range.from + prefix.length,
            range.from + prefix.length + sliced.length
        ),
        scrollIntoView: true,
    });
}

function abutsDoubledMarker(
    doc: { sliceString: (from: number, to: number) => string; length: number },
    outsideStart: number,
    outsideEnd: number,
    marker: string,
    singleChar: boolean
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
    singleChar: boolean
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
                if (before === prefix || after === prefix) continue;
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

    type LineInfo = { from: number; to: number; text: string; number: number };
    const lines: LineInfo[] = [];
    for (let n = startLine.number; n <= endLine.number; n++) {
        const line = state.doc.line(n);
        lines.push({ from: line.from, to: line.to, text: line.text, number: n });
    }

    const linesWithText = lines.filter((l) => l.text.length > 0);
    const allHavePrefix =
        linesWithText.length > 0 && linesWithText.every((l) => l.text.startsWith(prefix));

    const changes: ChangeSpec[] = [];
    let cursorLineNewEnd = sel.head;
    const cursorLineNumber = state.doc.lineAt(sel.head).number;
    let runningOffset = 0;

    for (const line of lines) {
        let newText: string;
        if (allHavePrefix) {
            // Removing prefix; empty lines stay empty.
            newText = line.text.length === 0 ? "" : line.text.slice(prefix.length);
        } else if (line.text.length === 0) {
            // Empty line: just add the prefix so the caret can start typing.
            newText = prefix;
        } else {
            const stripped = stripAnyBlockMarker(line.text);
            newText = stripped.startsWith(prefix) ? stripped : prefix + stripped;
        }

        if (newText !== line.text) {
            changes.push({ from: line.from, to: line.to, insert: newText });
        }

        const lineDelta = newText.length - line.text.length;
        const lineNewEnd = line.from + runningOffset + newText.length;
        runningOffset += lineDelta;

        if (line.number === cursorLineNumber) {
            cursorLineNewEnd = lineNewEnd;
        }
    }

    if (changes.length === 0) return;

    if (sel.from === sel.to) {
        // Empty selection: park the caret at the end of the (rewritten) cursor line.
        view.dispatch({
            changes,
            selection: EditorSelection.single(cursorLineNewEnd),
            scrollIntoView: true,
        });
    } else {
        // Multi-line range: re-select the rewritten block.
        const blockStart = lines[0].from;
        const blockNewLen =
            lines.reduce((sum, l, idx) => {
                const newLineText: string = (() => {
                    if (allHavePrefix) {
                        return l.text.length === 0 ? "" : l.text.slice(prefix.length);
                    }
                    if (l.text.length === 0) return prefix;
                    const stripped = stripAnyBlockMarker(l.text);
                    return stripped.startsWith(prefix) ? stripped : prefix + stripped;
                })();
                return sum + newLineText.length + (idx < lines.length - 1 ? 1 : 0);
            }, 0);
        view.dispatch({
            changes,
            selection: EditorSelection.single(blockStart, blockStart + blockNewLen),
            scrollIntoView: true,
        });
    }
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

// MARK: - Code block

function applyCodeBlock(view: EditorView) {
    const state = view.state;
    const sel = state.selection.main;
    if (sel.empty) {
        // Empty selection: insert ```\n\n``` and park caret on the empty line.
        const insertion = "```\n\n```";
        view.dispatch({
            changes: { from: sel.from, to: sel.to, insert: insertion },
            selection: EditorSelection.single(sel.from + 4),
            scrollIntoView: true,
        });
        return;
    }
    // Wrap the selection in a fenced code block.
    const sliced = state.doc.sliceString(sel.from, sel.to);
    const insertion = "```\n" + sliced + "\n```";
    view.dispatch({
        changes: { from: sel.from, to: sel.to, insert: insertion },
        selection: EditorSelection.single(sel.from + 4, sel.from + 4 + sliced.length),
        scrollIntoView: true,
    });
}

// MARK: - Link

function requestLinkPopover(view: EditorView, post: PostFn) {
    const state = view.state;
    const sel = state.selection.main;
    if (sel.empty) {
        // No selection → no link. The host doesn't even open the popover —
        // user has to select something first.
        return;
    }
    const start = view.coordsAtPos(sel.from, 1);
    const end = view.coordsAtPos(sel.to, -1);
    if (!start || !end) return;
    const x = Math.min(start.left, end.left);
    const right = Math.max(start.right, end.right);
    const y = Math.min(start.top, end.top);
    const bottom = Math.max(start.bottom, end.bottom);
    post({
        kind: "linkCreateRequest",
        from: sel.from,
        to: sel.to,
        rect: { x, y, width: right - x, height: bottom - y },
    });
}

interface LinkApplyPayload {
    from: number;
    to: number;
    url: string;
}

function applyLinkPayload(view: EditorView, arg: string | null) {
    if (!arg) return;
    let parsed: LinkApplyPayload;
    try {
        parsed = JSON.parse(arg);
    } catch {
        return;
    }
    const { from, to, url } = parsed;
    if (from < 0 || to > view.state.doc.length || from >= to) return;
    const text = view.state.sliceDoc(from, to);
    // If the range is already a complete link, replace just the URL portion.
    const linkPattern = /^\[([^\]]*)\]\(([^)]*)\)$/;
    const match = text.match(linkPattern);
    let insert: string;
    if (match) {
        insert = `[${match[1]}](${url})`;
    } else {
        insert = `[${text}](${url})`;
    }
    view.dispatch({
        changes: { from, to, insert },
        // Place caret just after the closing paren so subsequent typing is
        // outside the link.
        selection: EditorSelection.single(from + insert.length),
        scrollIntoView: true,
    });
    view.focus();
}

interface LinkRemovePayload {
    from: number;
    to: number;
}

function removeLinkPayload(view: EditorView, arg: string | null) {
    if (!arg) return;
    let parsed: LinkRemovePayload;
    try {
        parsed = JSON.parse(arg);
    } catch {
        return;
    }
    const { from, to } = parsed;
    if (from < 0 || to > view.state.doc.length || from >= to) return;
    const text = view.state.sliceDoc(from, to);
    const linkPattern = /^\[([^\]]*)\]\(([^)]*)\)$/;
    const match = text.match(linkPattern);
    if (!match) return;
    const inner = match[1];
    view.dispatch({
        changes: { from, to, insert: inner },
        selection: EditorSelection.single(from + inner.length),
        scrollIntoView: true,
    });
    view.focus();
}
