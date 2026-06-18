import Foundation

enum UpdateError: Error { case missingAsset, download, checksum, unpack, swap }

/// Downloads the latest release (app bundle + backend scripts), swaps the
/// running app bundle in place (APFS keeps the live process intact), refreshes
/// the backend scripts without touching user data, and relaunches via a
/// detached helper. The in-place swap happens *before* termination so the
/// KeepAlive LaunchAgent relaunches the new binary from the original path.
enum UpdateInstaller {
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Generates a detached relaunch helper. It waits for the running app to
    /// exit, de-quarantines + removes the .old backup, refreshes scripts
    /// (skipping user-owned files), and re-opens the app only if the KeepAlive
    /// LaunchAgent has not already brought it back.
    static func relaunchHelperScript(appPath: String, backupApp: String,
                                     scriptsZip: String?, installDir: String, pid: Int32,
                                     preserve: [String]) -> String {
        let q = shellQuote
        var script = """
        #!/bin/bash
        set -u
        shopt -s dotglob nullglob 2>/dev/null || true
        APP=\(q(appPath))
        BACKUP=\(q(backupApp))
        INSTALL=\(q(installDir))
        # 1) Wait for the old process to exit.
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        # 2) Drop quarantine on the freshly-installed bundle.
        /usr/bin/xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
        # 3) Remove the backup of the previous version.
        rm -rf "$BACKUP" 2>/dev/null || true

        """
        if let zip = scriptsZip {
            script += """
            # 4) Refresh backend scripts without touching user data.
            STAGE="$(mktemp -d)"
            /usr/bin/ditto -x -k \(q(zip)) "$STAGE" 2>/dev/null || true
            mkdir -p "$INSTALL"
            for f in "$STAGE"/*; do
              base="$(basename "$f")"
              case "$base" in

            """
            for p in preserve { script += "    \(p)) continue ;;\n" }
            script += """
              esac
              cp -f "$f" "$INSTALL/$base" 2>/dev/null || true
            done
            chmod +x "$INSTALL"/*.sh 2>/dev/null || true
            rm -rf "$STAGE" 2>/dev/null || true

            """
        }
        script += """
        # 5) Relaunch only if launchd (KeepAlive) did not already.
        sleep 1
        if ! /usr/bin/pgrep -f "$APP/Contents/MacOS/STTBar" >/dev/null 2>&1; then
          /usr/bin/open "$APP"
        fi
        """
        return script
    }

    /// Downloads + verifies + swaps the bundle in place, then spawns the helper.
    static func performUpdate(appZip: URL, scriptsZip: URL?, sha256: URL?,
                              appBundlePath: String, installDir: URL,
                              log: @escaping (String) -> Void,
                              done: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fm = FileManager.default
                let work = fm.temporaryDirectory.appendingPathComponent("STTBar-update-\(UUID().uuidString)")
                try fm.createDirectory(at: work, withIntermediateDirectories: true)

                log(L("Lade App…", "Downloading app…"))
                let appZipLocal = work.appendingPathComponent("STTBar.app.zip")
                try Data(contentsOf: appZip).write(to: appZipLocal)

                if let sha256 {
                    let expected = (try? String(contentsOf: sha256, encoding: .utf8))?
                        .trimmingCharacters(in: .whitespacesAndNewlines).prefix(64)
                    if let expected, !expected.isEmpty {
                        let actual = try sha256Hex(of: appZipLocal)
                        if actual.lowercased() != expected.lowercased() { throw UpdateError.checksum }
                    }
                }

                var scriptsZipLocal: URL?
                if let scriptsZip {
                    log(L("Lade Skripte…", "Downloading scripts…"))
                    let local = work.appendingPathComponent("stt-scripts.zip")
                    try Data(contentsOf: scriptsZip).write(to: local)
                    scriptsZipLocal = local
                }

                log(L("Entpacke…", "Unpacking…"))
                let stagedDir = work.appendingPathComponent("staged")
                try fm.createDirectory(at: stagedDir, withIntermediateDirectories: true)
                try run("/usr/bin/ditto", ["-x", "-k", appZipLocal.path, stagedDir.path])
                let stagedApp = stagedDir.appendingPathComponent("STTBar.app")
                guard fm.fileExists(atPath: stagedApp.path) else { throw UpdateError.unpack }
                try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", stagedApp.path])

                log(L("Installiere…", "Installing…"))
                let backup = appBundlePath + ".old"
                try? fm.removeItem(atPath: backup)
                // In-place swap while running (APFS keeps the live process intact).
                try fm.moveItem(atPath: appBundlePath, toPath: backup)
                do {
                    try run("/usr/bin/ditto", [stagedApp.path, appBundlePath])
                } catch {
                    // Roll back so the user is not left without an app.
                    try? fm.removeItem(atPath: appBundlePath)
                    try? fm.moveItem(atPath: backup, toPath: appBundlePath)
                    throw UpdateError.swap
                }

                let helper = work.appendingPathComponent("relaunch.sh")
                let helperText = relaunchHelperScript(
                    appPath: appBundlePath, backupApp: backup,
                    scriptsZip: scriptsZipLocal?.path, installDir: installDir.path,
                    pid: ProcessInfo.processInfo.processIdentifier,
                    preserve: [".env", "prompts.json", "profiles.json", "active-prompt.txt", "stt-replacements.tsv"])
                try helperText.write(to: helper, atomically: true, encoding: .utf8)

                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/bash")
                task.arguments = [helper.path]
                try task.run()  // detached; survives our termination

                done(.success(()))
            } catch {
                done(.failure(error))
            }
        }
    }

    private static func run(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw UpdateError.unpack }
    }

    private static func sha256Hex(of url: URL) throws -> String {
        let p = Process()
        let out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        p.arguments = ["-a", "256", url.path]
        p.standardOutput = out
        try p.run(); p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let line = String(data: data, encoding: .utf8) ?? ""
        return String(line.prefix(64))
    }
}
