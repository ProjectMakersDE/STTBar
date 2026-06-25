# STTBar — App Store Submission Notes (draft)

Draft prepared for the App Store Connect submission. Review and adjust before submitting. English, for Apple and the public listing.

## App Review notes (paste into App Store Connect "Notes for Reviewer")

STTBar is a menu bar dictation tool. The user presses a global hotkey, speaks, presses the hotkey again, and STTBar inserts the transcribed text into whatever text field currently has focus.

Accessibility usage and why it is required:
- The core function is inserting dictated text into the user's focused text field in any app. STTBar requests Accessibility permission to do this.
- Insertion is staged and prefers methods that do not use the clipboard: first the Accessibility API writes into the focused element, then synthesized Unicode keystrokes, and only as a last resort the clipboard plus Command V (the previous clipboard contents are saved and restored).
- The clipboard fallback always remains available, so the feature degrades gracefully if a target app does not support direct insertion.

How to test (reviewer steps):
1. Launch STTBar. It appears in the menu bar (no Dock icon).
2. Grant Microphone and Accessibility when prompted (System Settings > Privacy & Security).
3. In Settings, choose a transcription source. The simplest for review is "Built-in / local": pick a small model (for example "base") and tap "Load model" to download it once.
4. Open TextEdit, place the cursor in a document, press the dictation hotkey (default shown in Settings > Shortcuts), say a short sentence, then press the hotkey again.
5. The transcribed text is inserted at the cursor in TextEdit.

Notes:
- No account or login is required.
- "Built-in / local" runs entirely on device with no network use after the one-time model download.
- "Server URL" / "Self-host" send the recorded audio to a Whisper-compatible endpoint the user configures; this is disclosed in the privacy details.

## Privacy nutrition label (answers to prepare)

- Microphone: used to record audio for speech to text. Not linked to identity. Not used for tracking.
- Audio data handling:
  - Built-in / local mode: audio is processed on device only; nothing is transmitted.
  - Server / Self-host mode: the recorded audio is sent to the Whisper-compatible endpoint the user configures, solely to produce the transcription. STTBar itself collects nothing and has no backend.
- No analytics, no advertising, no tracking, no third party SDKs that collect data.
- Privacy policy URL: REQUIRED — provide a public URL before submission (Apple requires a privacy policy link even when no data is collected by the developer).

## Export compliance

- `ITSAppUsesNonExemptEncryption` is set to `false` in Info.plist (the app uses only standard OS networking over HTTPS for user-configured endpoints / model download, no proprietary crypto). Confirm the standard exemption answer in App Store Connect.

## Store listing (draft)

- Name: STTBar
- Subtitle (max 30 chars): Local dictation for your Mac
- Category: Productivity (or Utilities)
- Price: one-time purchase, 3,99 EUR tier (no in-app purchases, no StoreKit code)
- Keywords (draft): dictation, speech to text, whisper, transcription, voice, menu bar, offline, privacy
- Description (draft):
  STTBar turns speech into text anywhere on your Mac. Press a hotkey, speak, and the text lands in whatever field you are typing in. Choose fully offline transcription with a built-in local model, or connect your own Whisper-compatible server. An optional cleanup pass can tidy the text. Your dictation stays private: in local mode nothing leaves your Mac.
  Features: global hotkey dictation, on-device Whisper (no internet needed after the one-time model download), optional server or self-hosted transcription, optional LLM cleanup, word replacements, a compact recording HUD, and direct insertion into the focused field without disturbing your clipboard.
- Support URL: REQUIRED — provide before submission.
- Screenshots: 2560x1600 (or the required Mac sizes). Suggested shots: menu bar with HUD during recording, Settings transcription-source picker, local model picker, prompt/vocabulary screen.

## Build / signing (Phase 5 code — needs your Apple Distribution cert)

- The App Store build must be signed with an Apple Distribution certificate + an App Store provisioning profile, with Hardened Runtime + App Sandbox. The current `build-app.sh` signs with Developer ID (for direct distribution); the App Store track needs a separate signing path/profile.
- App Store upload expects an `.xcarchive` / `.pkg` (Apple Distribution installer), uploaded via Transporter, Xcode Organizer, or `xcrun altool`/`notarytool`. A thin `xcodebuild archive` wrapper around the SwiftPM target is likely required.
- Keep the existing Semantic Release `.zip` (Developer ID / GitHub release) flow separate from the App Store build.
- This packaging code can be written, but producing an actual uploadable build requires your Apple Distribution certificate + provisioning profile (only you can create those in your Apple Developer account).

## Open user-only checklist

- [ ] Apple Developer: create App ID `de.projectmakers.sttbar`, Apple Distribution certificate, App Store provisioning profile.
- [ ] App Store Connect: create the app record, set the 3,99 EUR price tier.
- [ ] Provide a privacy policy URL and a support URL.
- [ ] Fill the privacy nutrition label (microphone; server-mode audio transmission disclosure).
- [ ] Confirm export compliance (non-exempt encryption = false).
- [ ] Prepare screenshots + the description / keywords above.
- [ ] Paste the review notes above; submit for review.
