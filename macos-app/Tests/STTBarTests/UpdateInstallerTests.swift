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
}
