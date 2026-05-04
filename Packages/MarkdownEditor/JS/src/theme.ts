// Theme that adapts to macOS light/dark and matches Noter's HUD aesthetic:
// transparent background, secondary marker color, accent for links.

import { EditorView } from "@codemirror/view";
import { Extension } from "@codemirror/state";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags } from "@lezer/highlight";

export type EditorAppearance = "light" | "dark";

export function buildTheme(appearance: EditorAppearance): Extension {
    const isDark = appearance === "dark";
    const text = isDark ? "#f5f5f7" : "#1d1d1f";
    const secondary = isDark ? "rgba(245,245,247,0.55)" : "rgba(29,29,31,0.55)";
    const tertiary = isDark ? "rgba(245,245,247,0.35)" : "rgba(29,29,31,0.35)";
    const codeBg = isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.06)";
    const accent = isDark ? "#0a84ff" : "#0a84ff";
    const selectionBg = isDark ? "rgba(10,132,255,0.35)" : "rgba(10,132,255,0.22)";

    const editorTheme = EditorView.theme(
        {
            "&": {
                color: text,
                backgroundColor: "transparent",
                height: "100%",
                fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif",
                fontSize: "14px",
            },
            ".cm-content": {
                caretColor: text,
                padding: "12px 24px",
                lineHeight: "1.55",
            },
            ".cm-cursor": { borderLeftColor: text, borderLeftWidth: "2px" },
            "&.cm-focused": { outline: "none" },
            "&.cm-focused .cm-cursor": { borderLeftColor: text },
            ".cm-selectionBackground, ::selection": { backgroundColor: selectionBg },
            "&.cm-focused .cm-selectionBackground, &.cm-focused ::selection": {
                backgroundColor: selectionBg,
            },
            ".cm-activeLine": { backgroundColor: "transparent" },
            ".cm-gutters": { display: "none" },
            ".cm-scroller": { fontFamily: "inherit", overflowX: "hidden" },
            ".cm-line": { padding: "0" },
            ".cm-link": { color: accent },
        },
        { dark: isDark }
    );

    const highlight = HighlightStyle.define([
        { tag: tags.heading1, fontSize: "1.7em", fontWeight: "700" },
        { tag: tags.heading2, fontSize: "1.4em", fontWeight: "700" },
        { tag: tags.heading3, fontSize: "1.2em", fontWeight: "700" },
        { tag: tags.heading4, fontSize: "1.1em", fontWeight: "700" },
        { tag: tags.heading5, fontWeight: "700" },
        { tag: tags.heading6, fontWeight: "700" },
        { tag: tags.strong, fontWeight: "700" },
        { tag: tags.emphasis, fontStyle: "italic" },
        { tag: tags.strikethrough, textDecoration: "line-through" },
        { tag: tags.link, color: accent },
        { tag: tags.url, color: accent },
        {
            tag: tags.monospace,
            fontFamily: "ui-monospace, SF Mono, Menlo, monospace",
            backgroundColor: codeBg,
            padding: "1px 4px",
            borderRadius: "4px",
        },
        { tag: tags.processingInstruction, color: tertiary },
        { tag: tags.contentSeparator, color: tertiary },
        { tag: tags.meta, color: secondary },
        { tag: tags.comment, color: secondary, fontStyle: "italic" },
        { tag: tags.quote, color: secondary, fontStyle: "italic" },
        { tag: tags.list, color: secondary },
        { tag: tags.atom, color: secondary },
    ]);

    return [editorTheme, syntaxHighlighting(highlight)];
}
