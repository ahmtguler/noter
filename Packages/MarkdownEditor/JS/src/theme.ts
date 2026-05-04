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
    const accent = "#0a84ff";
    const selectionBg = isDark ? "rgba(10,132,255,0.35)" : "rgba(10,132,255,0.22)";
    const scrollThumb = isDark ? "rgba(255,255,255,0.18)" : "rgba(0,0,0,0.18)";
    const scrollThumbHover = isDark ? "rgba(255,255,255,0.32)" : "rgba(0,0,0,0.32)";

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
                padding: "12px 16px",
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
            ".cm-scroller": {
                fontFamily: "inherit",
                overflowX: "hidden",
                overflowY: "auto",
            },
            // Inset the scroll area so the scrollbar sits a few pixels from
            // the panel's right edge instead of touching it.
            ".cm-editor": { paddingRight: "4px" },
            ".cm-line": { padding: "0" },
            ".cm-link": { color: accent, textDecoration: "none" },
            ".cm-bullet-widget": { color: accent, fontWeight: "700", marginRight: "0px" },
            ".cm-numbered-marker": { color: accent, fontWeight: "600" },
            ".cm-task-checkbox": {
                display: "inline-block",
                width: "14px",
                height: "14px",
                border: `1.5px solid ${secondary}`,
                borderRadius: "3px",
                textAlign: "center",
                lineHeight: "11px",
                fontSize: "10px",
                fontWeight: "700",
                cursor: "pointer",
                marginRight: "6px",
                userSelect: "none",
                verticalAlign: "-2px",
                color: "transparent",
                transition: "background-color 0.1s, border-color 0.1s",
            },
            ".cm-task-checkbox-checked": {
                backgroundColor: accent,
                borderColor: accent,
                color: "white",
            },
            // Subtle scrollbar that hugs the right edge and dims when not hovered.
            ".cm-scroller::-webkit-scrollbar": {
                width: "6px",
                height: "6px",
            },
            ".cm-scroller::-webkit-scrollbar-track": {
                background: "transparent",
            },
            ".cm-scroller::-webkit-scrollbar-thumb": {
                background: scrollThumb,
                borderRadius: "3px",
            },
            ".cm-scroller::-webkit-scrollbar-thumb:hover": {
                background: scrollThumbHover,
            },
        },
        { dark: isDark }
    );

    // Custom highlight only — we deliberately skip the @codemirror/language
    // defaultHighlightStyle because it adds text-decoration: underline to
    // headings, which doesn't fit the live-preview aesthetic.
    const highlight = HighlightStyle.define([
        { tag: tags.heading1, fontSize: "1.7em", fontWeight: "700", textDecoration: "none" },
        { tag: tags.heading2, fontSize: "1.4em", fontWeight: "700", textDecoration: "none" },
        { tag: tags.heading3, fontSize: "1.2em", fontWeight: "700", textDecoration: "none" },
        { tag: tags.heading4, fontSize: "1.1em", fontWeight: "700", textDecoration: "none" },
        { tag: tags.heading5, fontWeight: "700", textDecoration: "none" },
        { tag: tags.heading6, fontWeight: "700", textDecoration: "none" },
        { tag: tags.strong, fontWeight: "700" },
        { tag: tags.emphasis, fontStyle: "italic" },
        { tag: tags.strikethrough, textDecoration: "line-through" },
        { tag: tags.link, color: accent, textDecoration: "none" },
        { tag: tags.url, color: accent, textDecoration: "none" },
        {
            tag: tags.monospace,
            fontFamily: "ui-monospace, SF Mono, Menlo, monospace",
            backgroundColor: codeBg,
            padding: "1px 4px",
            borderRadius: "4px",
        },
        // Markers (HeaderMark, EmphasisMark, etc.) get tertiary so they're
        // visible-but-quiet on the active line. They're hidden everywhere
        // else by livePreviewPlugin.
        { tag: tags.processingInstruction, color: tertiary },
        { tag: tags.contentSeparator, color: tertiary },
        { tag: tags.meta, color: secondary },
        { tag: tags.comment, color: secondary, fontStyle: "italic" },
        { tag: tags.quote, color: secondary, fontStyle: "italic" },
        // Intentionally NOT styling tags.list — that dimmed the entire list
        // line content. Marker glyphs are dimmed via the bullet widget /
        // theme already.
        { tag: tags.atom, color: secondary },
    ]);

    return [editorTheme, syntaxHighlighting(highlight)];
}
