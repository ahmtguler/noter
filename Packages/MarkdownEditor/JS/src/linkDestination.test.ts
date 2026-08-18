import { describe, expect, it } from "vitest";
import { decodeLinkDestination, encodeLinkDestination } from "./linkDestination";

describe("encodeLinkDestination", () => {
    it("leaves an ordinary URL untouched", () => {
        expect(encodeLinkDestination("https://example.com/a/b?c=1&d=2")).toBe(
            "https://example.com/a/b?c=1&d=2"
        );
    });

    // The regression: a bare ")" ends the destination, so the link was written
    // truncated and the rest of the URL landed in the note as plain text.
    it("wraps a URL containing parentheses", () => {
        expect(
            encodeLinkDestination("https://en.wikipedia.org/wiki/Cat_(disambiguation)")
        ).toBe("<https://en.wikipedia.org/wiki/Cat_(disambiguation)>");
    });

    it("wraps a URL containing spaces", () => {
        expect(encodeLinkDestination("https://example.com/a b")).toBe(
            "<https://example.com/a b>"
        );
    });

    it("escapes angle brackets inside a wrapped destination", () => {
        expect(encodeLinkDestination("https://example.com/a(b)<c>")).toBe(
            "<https://example.com/a(b)\\<c\\>>"
        );
    });

    it("does not double-wrap an already wrapped destination", () => {
        expect(encodeLinkDestination("<https://example.com/a(b)>")).toBe(
            "<https://example.com/a(b)>"
        );
    });
});

describe("decodeLinkDestination", () => {
    it("leaves a bare URL untouched", () => {
        expect(decodeLinkDestination("https://example.com")).toBe("https://example.com");
    });

    it("unwraps an angle-bracketed destination", () => {
        expect(
            decodeLinkDestination("<https://en.wikipedia.org/wiki/Cat_(disambiguation)>")
        ).toBe("https://en.wikipedia.org/wiki/Cat_(disambiguation)");
    });

    it("unescapes angle brackets", () => {
        expect(decodeLinkDestination("<https://example.com/a\\<c\\>>")).toBe(
            "https://example.com/a<c>"
        );
    });
});

describe("round trip", () => {
    // Clicking a link the editor itself wrote has to hand the host the
    // original URL, otherwise the fix for writing links breaks reading them.
    it.each([
        "https://example.com",
        "https://en.wikipedia.org/wiki/Cat_(disambiguation)",
        "https://example.com/a b",
        "https://example.com/a(b)<c>",
        "mailto:someone@example.com",
    ])("survives encode then decode: %s", (url) => {
        expect(decodeLinkDestination(encodeLinkDestination(url))).toBe(url);
    });
});
