import AppKit
import AVFoundation
import ApplicationServices

/// Helpers to query, trigger, and deep-link the system permissions STTBar
/// needs: Microphone (recording) and Accessibility (inserting text and sending
/// the ⌘V paste keystroke via synthesized CGEvents).
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

    // MARK: Open the relevant System Settings panes

    static func openAccessibility() { open("Privacy_Accessibility") }
    static func openMicrophone() { open("Privacy_Microphone") }

    private static func open(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
