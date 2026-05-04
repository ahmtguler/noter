// swift-tools-version: 5.10
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
