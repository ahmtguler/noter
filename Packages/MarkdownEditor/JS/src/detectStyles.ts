// Inspects the document around the caret to figure out which markdown styles
// are active right now. The result is sent across the bridge as a string array.

import { EditorState } from "@codemirror/state";

const STYLE_NAMES = [
    "heading1",
    "heading2",
    "heading3",
    "bold",
    "italic",
    "underline",
    "strikethrough",
    "code",
    "bulletList",
    "numberedList",
    "todoList",
    "quote",
] as const;

export type StyleName = (typeof STYLE_NAMES)[number];

export function detectActiveStyles(state: EditorState): StyleName[] {
    const sel = state.selection.main;
    const line = state.doc.lineAt(sel.from);
    const lineText = line.text;
    const styles = new Set<StyleName>();

    detectBlockStyles(lineText, styles);
    detectInlineStyles(lineText, sel.from - line.from, sel.to - line.from, styles);

    return STYLE_NAMES.filter((name) => styles.has(name));
}

function detectBlockStyles(line: string, out: Set<StyleName>) {
    const headingMatch = line.match(/^(#{1,6})\s+/);
    if (headingMatch) {
        const level = headingMatch[1].length;
        if (level === 1) out.add("heading1");
        else if (level === 2) out.add("heading2");
        else if (level === 3) out.add("heading3");
    }
    if (/^[-*+]\s+\[[xX ]\]\s+/.test(line)) {
        out.add("todoList");
    } else if (/^[-*+]\s+/.test(line)) {
        out.add("bulletList");
    }
    if (/^\d+\.\s+/.test(line)) {
        out.add("numberedList");
    }
    if (/^>\s+/.test(line)) {
        out.add("quote");
    }
}

function detectInlineStyles(
    line: string,
    relativeStart: number,
    relativeEnd: number,
    out: Set<StyleName>,
) {
    if (matchesInline(/\*\*\*([^*\n]+?)\*\*\*/g, line, relativeStart, relativeEnd)) {
        out.add("bold");
        out.add("italic");
    }
    if (matchesInline(/\*\*([^*\n]+?)\*\*/g, line, relativeStart, relativeEnd)) {
        out.add("bold");
    }
    if (matchesInline(/(?<!\*)\*([^*\n]+?)\*(?!\*)/g, line, relativeStart, relativeEnd)) {
        out.add("italic");
    }
    if (matchesInline(/~~([^~\n]+?)~~/g, line, relativeStart, relativeEnd)) {
        out.add("strikethrough");
    }
    if (matchesInline(/<u>([^<\n]+?)<\/u>/g, line, relativeStart, relativeEnd)) {
        out.add("underline");
    }
    if (matchesInline(/`([^`\n]+?)`/g, line, relativeStart, relativeEnd)) {
        out.add("code");
    }
}

function matchesInline(
    regex: RegExp,
    line: string,
    selStart: number,
    selEnd: number,
): boolean {
    let match: RegExpExecArray | null;
    while ((match = regex.exec(line)) !== null) {
        const innerStart = match.index + match[0].indexOf(match[1]);
        const innerEnd = innerStart + match[1].length;
        if (innerStart <= selStart && selEnd <= innerEnd) {
            return true;
        }
    }
    return false;
}
