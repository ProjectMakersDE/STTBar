import XCTest
@testable import STTBar

final class AudioInputResolverTests: XCTestCase {
    private let builtIn = AudioInputDeviceInfo(id: 1, name: "MacBook Pro-Mikrofon", transport: .builtIn)
    private let usb = AudioInputDeviceInfo(id: 2, name: "Scarlett 2i2 4th Gen", transport: .usb)
    private let airpods = AudioInputDeviceInfo(id: 3, name: "AirPods Pro von Simon-Daniel", transport: .bluetooth)
    private let virtualMic = AudioInputDeviceInfo(id: 4, name: "Loopback", transport: .other)

    private func resolve(selected: String = "",
                         avoidBluetooth: Bool = true,
                         devices: [AudioInputDeviceInfo],
                         defaultInput: AudioInputDeviceInfo?) -> AudioInputResolution {
        AudioInputResolver.resolve(selected: selected,
                                   avoidBluetooth: avoidBluetooth,
                                   devices: devices,
                                   defaultInput: defaultInput)
    }

    // MARK: Rule 1 — an explicit pick wins, Bluetooth included

    func testExplicitSelectionIsUsed() {
        let result = resolve(selected: "MacBook Pro-Mikrofon",
                             devices: [airpods, builtIn, usb],
                             defaultInput: airpods)
        XCTAssertEqual(result, .device(builtIn.id))
    }

    func testExplicitBluetoothSelectionBeatsTheGuard() {
        let result = resolve(selected: "AirPods Pro von Simon-Daniel",
                             avoidBluetooth: true,
                             devices: [airpods, builtIn],
                             defaultInput: builtIn)
        XCTAssertEqual(result, .device(airpods.id))
    }

    func testExplicitSelectionIgnoresSurroundingWhitespace() {
        let result = resolve(selected: "  MacBook Pro-Mikrofon\n",
                             devices: [airpods, builtIn],
                             defaultInput: airpods)
        XCTAssertEqual(result, .device(builtIn.id))
    }

    // MARK: Rule 2 — a disconnected pick falls through to the guard, not to the default

    func testDisconnectedSelectionFallsBackToNonBluetoothDevice() {
        let result = resolve(selected: "Scarlett 2i2 4th Gen",
                             devices: [airpods, builtIn],
                             defaultInput: airpods)
        XCTAssertEqual(result, .device(builtIn.id))
    }

    // MARK: Rule 3 — guard off means the system default, as before

    func testGuardOffKeepsSystemDefaultEvenOnBluetooth() {
        let result = resolve(avoidBluetooth: false,
                             devices: [airpods, builtIn],
                             defaultInput: airpods)
        XCTAssertEqual(result, .systemDefault)
    }

    func testNonBluetoothDefaultIsLeftAlone() {
        let result = resolve(devices: [airpods, builtIn, usb], defaultInput: usb)
        XCTAssertEqual(result, .systemDefault)
    }

    // MARK: Rule 4 — Bluetooth default is replaced, built-in first, then USB

    func testBluetoothDefaultPrefersBuiltInOverUsb() {
        let result = resolve(devices: [airpods, usb, builtIn], defaultInput: airpods)
        XCTAssertEqual(result, .device(builtIn.id))
    }

    func testBluetoothDefaultFallsBackToUsbWhenNoBuiltInExists() {
        let result = resolve(devices: [airpods, usb], defaultInput: airpods)
        XCTAssertEqual(result, .device(usb.id))
    }

    func testBluetoothDefaultFallsBackToAnyWiredInput() {
        let result = resolve(devices: [airpods, virtualMic], defaultInput: airpods)
        XCTAssertEqual(result, .device(virtualMic.id))
    }

    func testBluetoothLowEnergyCountsAsBluetooth() {
        let ble = AudioInputDeviceInfo(id: 5, name: "BLE Headset", transport: .bluetooth)
        let result = resolve(devices: [ble, builtIn], defaultInput: ble)
        XCTAssertEqual(result, .device(builtIn.id))
    }

    /// Recording at poor quality still beats refusing to record.
    func testBluetoothOnlySetupKeepsRecordingOnTheHeadset() {
        let result = resolve(devices: [airpods], defaultInput: airpods)
        XCTAssertEqual(result, .systemDefault)
    }

    func testUnknownDefaultInputKeepsSystemDefault() {
        let result = resolve(devices: [builtIn], defaultInput: nil)
        XCTAssertEqual(result, .systemDefault)
    }
}
