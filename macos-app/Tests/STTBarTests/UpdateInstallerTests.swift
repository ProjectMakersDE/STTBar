import XCTest
@testable import STTBar

final class UpdateInstallerTests: XCTestCase {
    func testPickAssetByName() {
        let json = """
        {"tag_name":"v1.1.0","html_url":"https://x/r","assets":[
          {"name":"STTBar.app.zip","browser_download_url":"https://x/app.zip"},
          {"name":"stt-scripts.zip","browser_download_url":"https://x/scripts.zip"},
          {"name":"STTBar.app.zip.sha256","browser_download_url":"https://x/app.sha"}
        ]}
        """.data(using: .utf8)!
        let release = try! JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertEqual(SettingsModel.pickAsset(release.assets, name: "STTBar.app.zip")?.absoluteString, "https://x/app.zip")
        XCTAssertEqual(SettingsModel.pickAsset(release.assets, name: "stt-scripts.zip")?.absoluteString, "https://x/scripts.zip")
        XCTAssertNil(SettingsModel.pickAsset(release.assets, name: "missing.zip"))
    }

    func testRelaunchHelperPreservesUserData() {
        let script = UpdateInstaller.relaunchHelperScript(
            appPath: "/Applications/STTBar.app",
            backupApp: "/Applications/STTBar.app.old",
            scriptsZip: "/tmp/u/stt-scripts.zip",
            installDir: "/Users/me/.local/share/stt",
            pid: 4242,
            preserve: [".env", "prompts.json", "profiles.json", "active-prompt.txt", "stt-replacements.tsv"])
        XCTAssertTrue(script.contains("kill -0 4242"))           // waits for app exit
        XCTAssertTrue(script.contains("ditto"))                   // extracts scripts zip
        XCTAssertTrue(script.contains("com.apple.quarantine"))    // de-quarantine
        XCTAssertTrue(script.contains("stt-replacements.tsv) continue")) // preserves user data
        XCTAssertTrue(script.contains("/Applications/STTBar.app")) // target path quoted in
    }

    func testRelaunchHelperWithoutScriptsZip() {
        let script = UpdateInstaller.relaunchHelperScript(
            appPath: "/Applications/STTBar.app",
            backupApp: "/Applications/STTBar.app.old",
            scriptsZip: nil,
            installDir: "/Users/me/.local/share/stt",
            pid: 7,
            preserve: [])
        XCTAssertTrue(script.contains("kill -0 7"))
        XCTAssertFalse(script.contains("stt-scripts.zip")) // no scripts step when absent
        XCTAssertTrue(script.contains("/usr/bin/open"))    // still relaunches
    }
}
