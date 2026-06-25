import Foundation

/// The wizard's ordered steps. `configure` shows the local-model download or the
/// server endpoint depending on the chosen source.
enum OnboardingStep: String, CaseIterable {
    case welcome, source, permissions, configure, hotkey, test, done
}

/// Drives the wizard: a linear step cursor plus a little live state the Test step
/// observes (forwarded from the runner by AppDelegate). UI-free so it is testable.
final class OnboardingModel: ObservableObject {
    let steps = OnboardingStep.allCases
    @Published var stepIndex = 0

    /// Live recording state mirrored from the runner while the wizard is open.
    @Published var liveState: SttState = .idle
    /// Last transcript produced during the wizard (Test step feedback).
    @Published var lastTestTranscript: String?

    var step: OnboardingStep { steps[stepIndex] }
    var canBack: Bool { stepIndex > 0 }
    var isLast: Bool { step == .done }

    /// 0…1 across the steps, for the progress bar.
    var progress: Double {
        steps.count <= 1 ? 1 : Double(stepIndex) / Double(steps.count - 1)
    }

    func next() {
        if stepIndex < steps.count - 1 { stepIndex += 1 }
    }

    func back() {
        if stepIndex > 0 { stepIndex -= 1 }
    }
}
