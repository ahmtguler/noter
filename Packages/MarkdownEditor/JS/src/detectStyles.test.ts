import { EditorState } from "@codemirror/state";
import { describe, expect, it } from "vitest";
import { detectActiveStyles, type StyleName } from "./detectStyles";

// `@codemirror/state` is a pure data model with no DOM, so a real EditorState
// can be built in plain Node. These are the styles the toolbar highlights, so a
// regression here shows up as buttons that look wrong rather than as a crash.
function stylesAt(doc: string, anchor: number, head: number = anchor): StyleName[] {
    return detectActiveStyles(EditorState.create({ doc, selection: { anchor, head } }));
}

describe("block styles", () => {
    it("detects heading levels 1 through 3", () => {
        expect(stylesAt("# Title", 3)).toEqual(["heading1"]);
        expect(stylesAt("## Title", 4)).toEqual(["heading2"]);
        expect(stylesAt("### Title", 5)).toEqual(["heading3"]);
    });

    // The toolbar only offers H1–H3, so deeper headings intentionally report
    // nothing rather than falling back to heading3.
    it("ignores heading levels beyond 3", () => {
        expect(stylesAt("#### Title", 6)).toEqual([]);
    });

    it("requires a space after the hashes", () => {
        expect(stylesAt("#NotAHeading", 5)).toEqual([]);
    });

    it("detects bullet lists for each marker", () => {
        expect(stylesAt("- item", 3)).toEqual(["bulletList"]);
        expect(stylesAt("* item", 3)).toEqual(["bulletList"]);
        expect(stylesAt("+ item", 3)).toEqual(["bulletList"]);
    });

    // A task is a bullet syntactically, but the toolbar treats them as distinct
    // buttons, so a checkbox line must not light up the plain bullet too.
    it("reports a task list as todoList only, not bulletList", () => {
        expect(stylesAt("- [ ] task", 7)).toEqual(["todoList"]);
        expect(stylesAt("- [x] done", 7)).toEqual(["todoList"]);
        expect(stylesAt("- [X] done", 7)).toEqual(["todoList"]);
    });

    it("detects numbered lists and quotes", () => {
        expect(stylesAt("1. item", 4)).toEqual(["numberedList"]);
        expect(stylesAt("> quoted", 4)).toEqual(["quote"]);
    });

    it("reports nothing for plain text", () => {
        expect(stylesAt("just some text", 5)).toEqual([]);
    });
});

describe("inline styles", () => {
    it("detects a caret inside each inline marker", () => {
        expect(stylesAt("**bold**", 4)).toEqual(["bold"]);
        expect(stylesAt("*ital*", 3)).toEqual(["italic"]);
        expect(stylesAt("~~struck~~", 5)).toEqual(["strikethrough"]);
        expect(stylesAt("`code`", 3)).toEqual(["code"]);
        expect(stylesAt("<u>under</u>", 5)).toEqual(["underline"]);
    });

    // Only the content between the markers counts as "inside", otherwise the
    // toolbar would show bold active while the caret sits after the closing **.
    it("reports nothing when the caret is outside the markers", () => {
        expect(stylesAt("**bold** tail", 11)).toEqual([]);
    });

    // The italic pattern uses look-around so a doubled marker isn't mistaken
    // for the inner edge of a single one — the same hazard commands.ts guards
    // against when unwrapping.
    it("does not report italic inside bold", () => {
        expect(stylesAt("**bold**", 4)).toEqual(["bold"]);
    });

    it("reports both for triple markers", () => {
        expect(stylesAt("***both***", 5)).toEqual(["bold", "italic"]);
    });

    it("detects a style spanning a whole selection", () => {
        // Select "bold" exactly inside **bold**.
        expect(stylesAt("**bold**", 2, 6)).toEqual(["bold"]);
    });

    it("reports nothing when the selection escapes the markers", () => {
        expect(stylesAt("**bold** tail", 2, 12)).toEqual([]);
    });
});

describe("combined styles", () => {
    it("reports block and inline styles together", () => {
        // Caret inside the bold run of a bullet item.
        expect(stylesAt("- **bold** item", 6)).toEqual(["bold", "bulletList"]);
    });

    it("reports styles in a stable declaration order", () => {
        // Regardless of where the styles came from, output follows STYLE_NAMES
        // so the Swift side sees a predictable set.
        expect(stylesAt("> **bold**", 6)).toEqual(["bold", "quote"]);
    });
});

describe("multi-line documents", () => {
    it("uses the line the caret is on", () => {
        const doc = "# Heading\n- item\nplain";
        expect(stylesAt(doc, 3)).toEqual(["heading1"]);
        expect(stylesAt(doc, 13)).toEqual(["bulletList"]);
        expect(stylesAt(doc, 19)).toEqual([]);
    });
});
