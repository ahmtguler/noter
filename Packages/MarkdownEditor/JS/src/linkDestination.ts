// Encoding and decoding of Markdown link destinations.
//
// Deliberately free of CodeMirror imports so it can be unit-tested in plain
// Node without a DOM.

/**
 * Renders a URL as a Markdown link destination, wrapping it in angle brackets
 * when a bare one would not survive a round trip.
 *
 * An unescaped ")" terminates the destination early, so confirming the link
 * popover with a URL like `https://en.wikipedia.org/wiki/Cat_(disambiguation)`
 * wrote a link that stopped at the first ")" and dumped the remainder into the
 * note as plain text — silently corrupting the document. Wikipedia
 * disambiguation pages, Jira and Confluence links, and plenty of query strings
 * all hit it; spaces break it the same way. CommonMark's angle-bracket form
 * covers both, and inside it only "<" and ">" still need escaping.
 */
export function encodeLinkDestination(url: string): string {
    if (url.startsWith("<") && url.endsWith(">")) return url;
    if (!/[()\s<>]/.test(url)) return url;
    return `<${url.replace(/[<>]/g, (character) => `\\${character}`)}>`;
}

/**
 * Unwraps an angle-bracketed destination back to a plain URL.
 *
 * The syntax tree's URL node spans the brackets, so without this the host
 * would be handed `<https://…>` and fail to open it — breaking exactly the
 * links the editor writes for itself.
 */
export function decodeLinkDestination(raw: string): string {
    if (raw.startsWith("<") && raw.endsWith(">")) {
        return raw.slice(1, -1).replace(/\\([<>])/g, "$1");
    }
    return raw;
}
