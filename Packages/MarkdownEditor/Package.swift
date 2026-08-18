// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkdownEditor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MarkdownEditor",
            targets: ["MarkdownEditor"]
        )
    ],
    targets: [
        .target(
            name: "MarkdownEditor",
            resources: [
                .copy("Resources/editor.html"),
                .copy("Resources/editor.bundle.js"),
                .copy("Resources/editor.css")
            ]
        ),
        .testTarget(
            name: "MarkdownEditorTests",
            dependencies: ["MarkdownEditor"]
        )
    ]
)
