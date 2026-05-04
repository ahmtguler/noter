// Input handlers that auto-convert common shortcuts into proper markdown:
// - Typing `[` then `]` at the start of a line auto-expands to `- [ ] `, so the
//   user can start a todo by just bracketing instead of remembering the dash.

import { EditorView } from "@codemirror/view";

export const todoBracketAutoComplete = EditorView.inputHandler.of((view, from, to, text) => {
    if (text !== "]") return false;
    if (from !== to) return false;

    const line = view.state.doc.lineAt(from);
    const beforeCursor = line.text.slice(0, from - line.from);
    if (!/^\s*\[$/.test(beforeCursor)) return false;

    const indent = beforeCursor.slice(0, -1); // drop the trailing `[`
    const replacement = `${indent}- [ ] `;
    view.dispatch({
        changes: { from: line.from, to: from, insert: replacement },
        selection: { anchor: line.from + replacement.length },
        scrollIntoView: true,
    });
    return true;
});
