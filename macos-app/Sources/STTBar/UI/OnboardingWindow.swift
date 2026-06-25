import AppKit
import SwiftUI

/// Hosts `OnboardingView` in a small titled window. Owns the wizard's flow state
/// so AppDelegate can mirror the runner's live state into the Test step.
final class OnboardingWindow {
    private var window: NSWindow?
    let flow = OnboardingModel()
    private let model: SettingsModel

    /// Triggers a raw recording for the Test step.
    var onStartRawTest: () -> Void = {}
    /// Called after the user finishes (flag already marked).
    var onCompleted: () -> Void = {}

    init(model: SettingsModel) {
        self.model = model
    }

    func show(reset: Bool = true) {
        if reset { flow.stepIndex = 0 }
        if window == nil {
            let host = NSHostingController(rootView: OnboardingView(
                model: model,
                flow: flow,
                onFinish: { [weak self] in self?.finish() },
                onStartRawTest: { [weak self] in self?.onStartRawTest() }))
            let w = NSWindow(contentViewController: host)
            w.title = L("STTBar – Einrichtung", "STTBar – Setup")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        OnboardingReadiness.markCompleted()
        model.applyEnvChanges()
        onCompleted()
        window?.close()
    }
}
