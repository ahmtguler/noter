import AppKit
import SwiftUI

/// In-editor floating popover for links. Sits as an overlay over the
/// EditorWebView (same SwiftUI hosting view), so it can never escape the
/// note window — unlike NSPopover which shows in its own window. Position
/// is computed from the link/selection rect emitted by JS, clamped to the
/// overlay bounds, and flipped above the link if there's no room below.
struct LinkPopoverOverlay: View {
    @ObservedObject var state: LinkPopoverState

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let active = state.active {
                    // Backdrop captures outside-clicks for dismissal — uses a
                    // hair of opacity so SwiftUI registers it for hit-testing.
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { state.close() }

                    popoverContent(active: active)
                        .background(
                            PopoverBackground()
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.30), radius: 12, y: 4)
                        .frame(width: popoverWidth(active.mode))
                        .offset(position(in: geo.size, for: active))
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                        )
                }
            }
            .animation(.easeOut(duration: 0.15), value: state.active)
        }
        .allowsHitTesting(state.active != nil)
    }

    @ViewBuilder
    private func popoverContent(active: LinkPopoverState.Active) -> some View {
        switch active.mode {
        case let .inspect(url):
            LinkInspectView(
                url: url,
                onCopy: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(url, forType: .string)
                    state.close()
                },
                onEdit: {
                    state.presentEdit(
                        initialURL: url,
                        range: active.range,
                        rect: active.rect,
                        kind: .editExisting
                    )
                }
            )
        case let .edit(initialURL, kind):
            LinkEditView(
                initialURL: initialURL,
                onCommit: { url in
                    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    state.onApplyLink?(active.range.lowerBound, active.range.upperBound, trimmed)
                    state.close()
                },
                onTrash: {
                    if kind == .editExisting {
                        state.onRemoveLink?(active.range.lowerBound, active.range.upperBound)
                    }
                    state.close()
                }
            )
        }
    }

    /// Width budget per mode so .offset() can clamp correctly even before the
    /// content is measured. Inspect is tighter; edit needs room for the
    /// TextField + buttons.
    private func popoverWidth(_ mode: LinkPopoverState.Mode) -> CGFloat {
        switch mode {
        case .inspect: 280
        case .edit: 320
        }
    }

    /// Estimated height — used only for clamping vertically. Slightly
    /// generous so a flipped popover never clips the bottom of the link.
    private func popoverHeight(_ mode: LinkPopoverState.Mode) -> CGFloat {
        switch mode {
        case .inspect: 42
        case .edit: 50
        }
    }

    /// Material-backed popover background. Lives in the package so the link
    /// popover doesn't need anything from the host app's view hierarchy.
    private struct PopoverBackground: NSViewRepresentable {
        func makeNSView(context _: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = .popover
            view.blendingMode = .withinWindow
            view.state = .active
            view.isEmphasized = true
            return view
        }

        func updateNSView(_: NSVisualEffectView, context _: Context) {}
    }

    private func position(in container: CGSize, for active: LinkPopoverState.Active) -> CGSize {
        let width = popoverWidth(active.mode)
        let height = popoverHeight(active.mode)
        let margin: CGFloat = 6
        let gap: CGFloat = 4

        let preferredX = active.rect.x
        let maxX = max(margin, container.width - width - margin)
        let x = min(max(margin, preferredX), maxX)

        let belowY = active.rect.y + active.rect.height + gap
        let aboveY = active.rect.y - height - gap
        let y: CGFloat = if belowY + height + margin <= container.height {
            belowY
        } else if aboveY >= margin {
            aboveY
        } else {
            max(margin, container.height - height - margin)
        }
        return CGSize(width: x, height: y)
    }
}
