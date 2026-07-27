import XCTest
@testable import STTBar

/// The health checks read the 256 KB event-journal tail and make a synchronous
/// XPC round-trip to `smd` (`SMAppService.status`). The 2 s watchdog ran them
/// on the main thread even while no window displayed the result, which starved
/// the 60 fps HUD redraw and stalled menu tracking. The refresh is therefore
/// gated on an explicit observer that `StatusWindow` owns.
final class HealthCenterModelTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HealthCenterModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeModel() -> HealthCenterModel {
        HealthCenterModel(settings: SettingsModel(installDir: dir),
                          runner: SttRunner(backend: PlaceholderBackend()))
    }

    /// A model nobody looks at must not have run a single check.
    func testFreshModelRunsNoChecksUntilObserved() {
        XCTAssertTrue(makeModel().checks.isEmpty)
    }

    /// The watchdog tick is a no-op while no window displays the model. This is
    /// the actual fix: on an idle app this path ran ~33-96 ms every 2 s.
    func testRefreshIfObservedSkipsWorkWhileUnobserved() {
        let model = makeModel()
        model.refreshIfObserved()
        XCTAssertTrue(model.checks.isEmpty)
    }

    /// Opening the window starts observing and fills the checks immediately, so
    /// the window never shows an empty list waiting for the next tick.
    func testBeginObservingRunsChecks() {
        let model = makeModel()
        model.beginObserving()
        XCTAssertFalse(model.checks.isEmpty)
    }

    /// While the window is open the watchdog keeps the checks live.
    func testRefreshIfObservedRunsWhileObserved() {
        let model = makeModel()
        model.beginObserving()
        model.checks = []
        model.refreshIfObserved()
        XCTAssertFalse(model.checks.isEmpty)
    }

    /// Closing the window must put the tick back to sleep.
    func testEndObservingStopsTheWatchdogRefresh() {
        let model = makeModel()
        model.beginObserving()
        model.endObserving()
        model.checks = []
        model.refreshIfObserved()
        XCTAssertTrue(model.checks.isEmpty)
    }
}
