// Click + hover behaviour for rendered Markdown links.
//
// - Plain click → opens the URL via the Swift host (`openURL`).
// - Hover for 250ms → posts `linkInspect` so the host can show a popover
//   with Copy / Edit. The hover position is reported in WKWebView-relative
//   coordinates (`getBoundingClientRect`); the host translates if needed.
//
// Link nodes come straight from `@codemirror/lang-markdown`'s syntax tree,
// not from any class on the rendered DOM, so we recover them by resolving
// the document position at the cursor.

import { EditorView } from "@codemirror/view";
import { syntaxTree } from "@codemirror/language";
import { decodeLinkDestination } from "./linkDestination";

interface BridgePost {
    (msg: object): void;
}

interface LinkAtPos {
    url: string;
    from: number;
    to: number;
}

const HOVER_DELAY_MS = 300;

export function makeLinkInteractions(post: BridgePost) {
    let hoverTimer: number | null = null;
    let lastHoveredFrom: number | null = null;

    function clearHover() {
        if (hoverTimer != null) {
            window.clearTimeout(hoverTimer);
            hoverTimer = null;
        }
        lastHoveredFrom = null;
    }

    return EditorView.domEventHandlers({
        click(event, view) {
            const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
            if (pos == null) return false;
            const link = linkAt(view, pos);
            if (!link) return false;
            event.preventDefault();
            event.stopPropagation();
            post({ kind: "openURL", url: link.url });
            return true;
        },
        mousemove(event, view) {
            const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
            if (pos == null) {
                clearHover();
                return false;
            }
            const link = linkAt(view, pos);
            if (!link) {
                clearHover();
                return false;
            }
            // Same link as last poll — let the existing timer ride.
            if (link.from === lastHoveredFrom) return false;
            clearHover();
            lastHoveredFrom = link.from;
            hoverTimer = window.setTimeout(() => {
                hoverTimer = null;
                const rect = linkRect(view, link);
                if (!rect) return;
                post({
                    kind: "linkInspect",
                    url: link.url,
                    from: link.from,
                    to: link.to,
                    rect,
                });
            }, HOVER_DELAY_MS);
            return false;
        },
        mouseleave(_event, _view) {
            clearHover();
            return false;
        },
    });
}

/// Returns the on-screen bounds of the visible link text (which is what the
/// user actually sees, since the URL portion is hidden by livePreview). Uses
/// `coordsAtPos` from CodeMirror so we get the line-rendered geometry rather
/// than any source-text DOM node.
function linkRect(
    view: EditorView,
    link: LinkAtPos
): { x: number; y: number; width: number; height: number } | null {
    // The visible portion of `[text](url)` is `text` — coords on the inner
    // bracket boundary give us the start of the visible text, and one
    // position before the closing bracket gives the end.
    const visibleStart = link.from + 1; // skip "["
    const visibleEnd = findVisibleEnd(view, link);
    const start = view.coordsAtPos(visibleStart, 1);
    const end = view.coordsAtPos(visibleEnd, -1);
    if (!start || !end) return null;
    const x = Math.min(start.left, end.left);
    const right = Math.max(start.right, end.right);
    const y = Math.min(start.top, end.top);
    const bottom = Math.max(start.bottom, end.bottom);
    return { x, y: y, width: right - x, height: bottom - y };
}

/// Finds the position right before the closing `]` so coordsAtPos lands on
/// the last visible character. Falls back to `link.to - 1` if the doc text
/// doesn't match the expected shape.
function findVisibleEnd(view: EditorView, link: LinkAtPos): number {
    const text = view.state.sliceDoc(link.from, link.to);
    const close = text.indexOf("](");
    if (close < 0) return link.to - 1;
    return link.from + close;
}

/// Walks the syntax tree at `pos` for an enclosing Link node and returns
/// {url, from, to} of the full link expression. Null if not inside a link.
function linkAt(view: EditorView, pos: number): LinkAtPos | null {
    const tree = syntaxTree(view.state);
    let node = tree.resolveInner(pos, -1);
    while (node) {
        if (node.type.name === "Link") {
            let urlNode = node.firstChild;
            while (urlNode) {
                if (urlNode.type.name === "URL") {
                    const raw = view.state.sliceDoc(urlNode.from, urlNode.to).trim();
                    return { url: decodeLinkDestination(raw), from: node.from, to: node.to };
                }
                urlNode = urlNode.nextSibling;
            }
            return null;
        }
        if (!node.parent) return null;
        node = node.parent;
    }
    return null;
}
