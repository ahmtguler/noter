import AppKit
import SwiftUI

/// Small hover/press-aware icon button used inside the link popovers.
/// Mirrors the styling used in Noter's switcher / palette rows so the
/// popovers feel native to the app even though they live in the package.
struct IconButton: View {
    let systemName: String
    let tooltip: String
    var tint: Color?
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint.map { AnyShapeStyle($0) }
                ?? AnyShapeStyle(HierarchicalShapeStyle.primary))
            .frame(width: 24, height: 24)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in
                        if isPressed { action() }
                        isPressed = false
                    }
            )
            .background(NativeTooltipBridge(text: tooltip))
    }

    private var background: Color {
        if isPressed { return Color.primary.opacity(0.15) }
        if isHovering { return Color.primary.opacity(0.08) }
        return .clear
    }
}

/// Internal AppKit tooltip bridge — SwiftUI's `.help()` doesn't surface on
/// borderless icon buttons inside an NSPopover.
private struct NativeTooltipBridge: NSViewRepresentable {
    let text: String

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        nsView.toolTip = text
    }
}
