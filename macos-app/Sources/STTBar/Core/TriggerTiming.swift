import Foundation

/// Pure timing math for hotkey instrumentation.
///
/// We can only size the double-fire window honestly if we know how far apart
/// the raw hotkey events actually land — and the log's one-second resolution is
/// far too coarse for that. This measures two things, in milliseconds:
///
/// - `intervalMs`: the gap to the *previous raw hotkey event* (whatever the
///   debounce later decides). Hardware/OS double-fires of a single physical
///   press show up here as tiny values; deliberate second presses as large ones.
/// - `latencyMs`: how long the event sat between arriving (captured in the
///   Carbon callback) and being handled on the main thread. A large value here
///   means a press was delayed by a busy main thread — the "it hangs" feeling —
///   rather than lost.
struct TriggerTiming: Equatable {
    /// Milliseconds since the previous raw hotkey event; nil for the first.
    let intervalMs: Int?
    /// Milliseconds between the event arriving and being handled on main.
    let latencyMs: Int

    init(previousRawEventAt: Date?, eventAt: Date, handledAt: Date) {
        intervalMs = previousRawEventAt.map { Int((eventAt.timeIntervalSince($0) * 1000).rounded()) }
        latencyMs = Int((max(0, handledAt.timeIntervalSince(eventAt)) * 1000).rounded())
    }

    /// Log token for the interval: the real millisecond count, or "first".
    var intervalToken: String { intervalMs.map(String.init) ?? "first" }
}
