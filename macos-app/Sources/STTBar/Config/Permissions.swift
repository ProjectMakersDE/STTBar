import AppKit
import AVFoundation
import ApplicationServices

/// Helpers to query, trigger, and deep-link the system permissions STTBar
/// needs: Microphone (recording), Accessibility (sending the ⌘V paste
/// keystroke) and Automation (controlling "System Events" for that keystroke).
enum Permissions {

    // MARK: Status

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    // MARK: Trigger the system prompts

    /// Shows the Accessibility "add this app" prompt if not yet trusted.
    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    /// Sends a harmless AppleEvent to "System Events" so macOS shows the
    /// "STTBar wants to control System Events" Automation consent prompt.
    static func primeAutomation() {
        DispatchQueue.global().async {
            let script = NSAppleScript(source:
                "tell application \"System Events\" to return name of first application process")
            var err: NSDictionary?
            _ = script?.executeAndReturnError(&err)
        }
    }

    // MARK: Open the relevant System Settings panes

    static func openAccessibility() { open("Privacy_Accessibility") }
    static func openMicrophone() { open("Privacy_Microphone") }
    static func openAutomation() { open("Privacy_Automation") }

    private static func open(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
