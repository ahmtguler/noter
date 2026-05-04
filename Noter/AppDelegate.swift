import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var menuBarController: MenuBarController?
    private var onboardingController: OnboardingWindowController?
    private(set) var app: AppViewModel?

    func applicationDidFinishLaunching(_: Notification) {
        do {
            let viewModel = try AppViewModel()
            app = viewModel

            let controller = PanelController(contentFactory: {
                AnyView(RootView(app: viewModel))
            })
            controller.onWillShow = { [weak controller] in
                guard let controller else { return }
                let minutes = UserDefaults.standard.object(forKey: SettingsKey.idleNewNoteMinutes) as? Int
                    ?? SettingsKey.defaultIdleNewNoteMinutes
                guard minutes > 0,
                      let lastHiddenAt = controller.lastHiddenAt,
                      Date().timeIntervalSince(lastHiddenAt) > Double(minutes) * 60
                else { return }
                viewModel.editor.startBlankDraft()
            }
            panelController = controller

            menuBarController = MenuBarController { [weak controller] in
                controller?.toggle()
            }
            KeyboardShortcuts.onKeyDown(for: .toggleNoter) { [weak controller] in
                controller?.toggle()
            }

            if !UserDefaults.standard.bool(forKey: SettingsKey.didOnboard) {
                showOnboarding(app: viewModel, after: controller)
            }
        } catch {
            presentFatalError("Failed to initialize Noter: \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_: Notification) {
        app?.editor.flush()
    }

    private func showOnboarding(app: AppViewModel, after controller: PanelController) {
        let onboarding = OnboardingWindowController(app: app) { [weak self] in
            self?.onboardingController = nil
            controller.show()
        }
        onboardingController = onboarding
        onboarding.show()
    }

    private func presentFatalError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Noter could not start"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
