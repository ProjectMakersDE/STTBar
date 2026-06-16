import Foundation

/// Writes/removes the login LaunchAgent that starts STTBar.app.
enum LaunchAgent {
    static let label = "de.projectmakers.sttbar"
    static var plistURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    /// `appPath` is the .app bundle path; `installDir` is exported so the agent
    /// finds the shell scripts + .env.
    static func setEnabled(_ on: Bool, appPath: String, installDir: String) {
        if on {
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>Label</key><string>\(label)</string>
              <key>ProgramArguments</key><array>
                <string>\(appPath)/Contents/MacOS/STTBar</string>
              </array>
              <key>EnvironmentVariables</key><dict>
                <key>STT_INSTALL_DIR</key><string>\(installDir)</string>
              </dict>
              <key>RunAtLoad</key><true/>
              <key>KeepAlive</key><true/>
            </dict></plist>
            """
            try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? plist.write(to: plistURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }
}
