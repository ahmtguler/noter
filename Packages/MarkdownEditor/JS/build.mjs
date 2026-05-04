import * as esbuild from "esbuild";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const outFile = path.resolve(__dirname, "../Sources/MarkdownEditor/Resources/editor.bundle.js");

const watch = process.argv.includes("--watch");

const options = {
    entryPoints: [path.resolve(__dirname, "src/index.ts")],
    bundle: true,
    format: "iife",
    target: ["safari16"],
    minify: !watch,
    sourcemap: watch ? "inline" : false,
    outfile: outFile,
    logLevel: "info",
    legalComments: "none",
    define: {
        "process.env.NODE_ENV": watch ? "\"development\"" : "\"production\"",
    },
};

if (watch) {
    const ctx = await esbuild.context(options);
    await ctx.watch();
    console.log(`[markdown-editor] watching for changes; output: ${outFile}`);
} else {
    await esbuild.build(options);
    console.log(`[markdown-editor] built: ${outFile}`);
}
