// Detects clicks on rendered Markdown links and forwards the URL to Swift
// so the host can open it via `NSWorkspace`. The WKWebView itself never
// navigates — letting it would tear the editor down.
//
// CodeMirror's lang-markdown wraps the link text in syntax-tree Link nodes;
// we walk the syntax tree at the click position to recover the link's URL
// regardless of where exactly the click landed inside the link span.

import { EditorView } from "@codemirror/view";
import { syntaxTree } from "@codemirror/language";

interface BridgePost {
    (msg: object): void;
}

export function makeLinkClickHandler(post: BridgePost) {
    return EditorView.domEventHandlers({
        click(event, view) {
            const target = event.target as HTMLElement | null;
            if (!target) return false;
            // Walk up looking for a CodeMirror line content; bail otherwise.
            const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
            if (pos == null) return false;
            const url = linkURLAt(view, pos);
            if (!url) return false;
            event.preventDefault();
            event.stopPropagation();
            post({ kind: "openURL", url });
            return true;
        },
    });
}

/// Scans the syntax tree at `pos` for an enclosing Link node and returns the
/// URL portion as plain text. Returns null if the position is not inside a
/// link.
function linkURLAt(view: EditorView, pos: number): string | null {
    const tree = syntaxTree(view.state);
    let node = tree.resolveInner(pos, -1);
    while (node) {
        if (node.type.name === "Link") {
            // Inside a Link node, find a child URL node and read its text.
            let urlNode = node.firstChild;
            while (urlNode) {
                if (urlNode.type.name === "URL") {
                    return view.state.sliceDoc(urlNode.from, urlNode.to).trim();
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
