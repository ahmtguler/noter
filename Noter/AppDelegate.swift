import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var menuBarController: MenuBarController?
    private var onboardingController: OnboardingWindowController?
    private var preferencesController: PreferencesWindowController?
    private var preferencesObserver: NSObjectProtocol?
    private(set) var app: AppViewModel?

    func applicationDidFinishLaunching(_: Notification) {
        do {
            let viewModel = try AppViewModel()
            app = viewModel

            let controller = PanelController(contentFactory: {
                AnyView(RootContainerView(app: viewModel))
            })
            controller.onWillShow = { [weak controller] in
                // Cheap opportunistic purge — runs every time the popup opens
                // so trash entries older than 14 days don't accumulate even
                // if the app is left running for weeks.
                viewModel.store.purgeExpiredTrash()
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
            preferencesController = PreferencesWindowController(app: viewModel)

            menuBarController = MenuBarController(
                onToggle: { [weak controller] in controller?.toggle() },
                onShow: { [weak controller] in controller?.show() },
                onShowPreferences: { [weak self] in self?.showPreferences() }
            )
            KeyboardShortcuts.onKeyDown(for: .toggleNoter) { [weak controller] in
                controller?.toggle()
            }

            preferencesObserver = NotificationCenter.default.addObserver(
                forName: .noterShowPreferences,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.showPreferences()
                }
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
        if let observer = preferencesObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func showPreferences() {
        preferencesController?.show()
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
