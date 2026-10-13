"""Reproduce review findings with unchanged release sources and synthetic data.

No microphone, clipboard, Keychain, live services or real user data are used.
Pass the v1.7.0 checkout path as the first argument. Generated fixtures are
confined to this report's .scratch directory, which is removed after the run.
"""
from pathlib import Path
import json
import shutil
import subprocess
import sys

repo = Path(sys.argv[1]).resolve()
out = Path(__file__).resolve().parent
scratch = out / '.scratch'
scratch.mkdir(exist_ok=True)
src = repo / 'macos-app/Sources/STTBar'

def run(name, files, main):
    folder = scratch / name
    folder.mkdir(exist_ok=True)
    (folder / 'main.swift').write_text(main)
    cmd = ['swiftc'] + [str(src / f) for f in files] + [str(folder / 'main.swift'), '-o', str(folder / 'check')]
    subprocess.run(cmd, check=True, capture_output=True, text=True)
    result = subprocess.run([str(folder / 'check'), str(folder)], check=True, capture_output=True, text=True)
    return result.stdout.strip()

def method(text, name):
    start = text.index('    func ' + name + '(')
    brace = text.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

env_result = run('env', ['Config/EnvStore.swift'], r'''
import Foundation
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let url = folder.appendingPathComponent(".env")
var env = try EnvStore(url: url)
env.set("STT_SOURCE", "local")
do { try env.save(); print("fresh_save=success") }
catch { let e = error as NSError; print("fresh_save=failed domain=\(e.domain) code=\(e.code)") }
print("fresh_destination_exists=\(FileManager.default.fileExists(atPath: url.path))")
try "STT_SOURCE=\"server\"\n".write(to: url, atomically: true, encoding: .utf8)
var existing = try EnvStore(url: url)
existing.set("STT_SOURCE", "local")
try existing.save()
print("existing_save=success source=\(try EnvStore(url: url).value("STT_SOURCE") ?? "missing")")
''')

runner_result = run('runner', ['Core/SttRunner.swift', 'Core/TranscriptionBackend.swift', 'Core/RecordingToggle.swift', 'Core/TriggerTiming.swift', 'Core/RuntimePaths.swift'], r'''
import Foundation
enum SttMode: String { case full, raw, english }
enum NativePasteResult { case pasted; case clipboardOnly(String) }
enum NativePaste { static func copyAndPaste(_ text: String, completion: @escaping (NativePasteResult) -> Void) { completion(.pasted) } }
func L(_ de: String, _ en: String) -> String { en }
struct SttStatus {}
enum StatusStore {
 static func writeAppStatus(event: String, phase: String, severity: String, code: String? = nil, message: String, detail: String? = nil) {}
 static func latestProblem(limit: Int) -> SttStatus? { nil }
}
enum AppLogger { static func log(_ message: String) {} }
final class AppSettings { static let shared = AppSettings(); var sensitiveMode = true }
final class FakeBackend: TranscriptionBackend {
 var isRecording = false
 func start(mode: SttMode) throws {
  isRecording = true
  try Data("synthetic private audio fixture".utf8).write(to: RuntimePaths.recordingFile)
 }
 func stop(mode: SttMode, onPhase: @escaping (TranscriptionPhase) -> Void, completion: @escaping (Result<String, Error>) -> Void) {
  isRecording = false
  completion(.failure(NSError(domain: "SyntheticWhisperTimeout", code: 1)))
 }
 func cancel() { isRecording = false; try? FileManager.default.removeItem(at: RuntimePaths.recordingFile) }
}
setenv("STT_RUNTIME_DIR", CommandLine.arguments[1], 1)
let runner = SttRunner(backend: FakeBackend())
runner.paste = { _, _ in fatalError("failure must not paste") }
runner.trigger(mode: .raw)
runner.stopAndTranscribe()
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
print("sensitive_failure_state=\(runner.state)")
print("sensitive_failure_wav_exists=\(FileManager.default.fileExists(atPath: RuntimePaths.recordingFile.path))")
''')

history_result = run('history', ['Core/TranscriptHistoryStore.swift'], r'''
import Foundation
func NSHomeDirectory() -> String { CommandLine.arguments[1] }
enum SttMode: String { case full, raw, english }
final class AppSettings {
 static let shared = AppSettings()
 var historyEnabled = true
 var sensitiveMode = false
 var historyRetentionHours = 1
}
let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/STTBar")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
var old = TranscriptHistoryItem(mode: "raw", text: "synthetic expired transcript")
old.date = Date().addingTimeInterval(-48 * 3600)
try JSONEncoder().encode([old]).write(to: dir.appendingPathComponent("transcript-history.json"))
let history = TranscriptHistoryStore()
print("expired_on_load=\(history.items.count)")
AppSettings.shared.sensitiveMode = true
history.add(text: "new sensitive fixture", mode: .raw)
print("expired_after_sensitive_add=\(history.items.count)")
AppSettings.shared.sensitiveMode = false
history.add(text: "new public fixture", mode: .raw)
print("expired_after_normal_add=\(history.items.filter { $0.text == old.text }.count)")
''')

settings_source = (src / 'Config/SettingsModel.swift').read_text()
privacy_main = r'''
import Foundation
func L(_ de: String, _ en: String) -> String { en }
struct FakeEnv { func save() throws {} }
final class Model {
 var whisperURL="http://localhost:8082", whisperModel="m", language="de", transcribeTimeout="30", whisperPrompt=""
 var vadFilter=true, temperatureFallback=true, postprocessEnabled=false, autoRawFallback=true, prewarmEnabled=false
 var lmStudioURL="http://localhost:1234", llmModel="m", provider="openai", beamSize="1"
 var postprocessTimeout="30", postprocessWarnSeconds="10", keepModelWarmSeconds="0", maxRecordingSeconds="60", historyRetentionHours="24"
 var historyEnabled=true, sensitiveMode=false, avoidBluetoothMic=true
 var audioInputDevice="", transcriptionSource="local", localModel="base"
 var validationMessage: String?, saveMessage: String?
 var effectiveSensitiveMode=false
 let env=FakeEnv()
 func backupEnv() {}
 func write(_ key: String, _ value: String) {}
 func saveApiKeys() {}
 func syncAppSettingsFromDraft() { effectiveSensitiveMode=sensitiveMode }
'''
privacy_main += method(settings_source, 'applyEnvChanges') + '\n' + method(settings_source, 'validateDraft')
privacy_main += r'''
}
let model=Model()
model.historyRetentionHours="24h"
model.sensitiveMode=true
model.applyEnvChanges()
print("sensitive_draft=\(model.sensitiveMode) effective_sensitive=\(model.effectiveSensitiveMode) validation=\(model.validationMessage ?? "none")")
model.historyRetentionHours="24"
model.whisperURL="not a URL"
model.applyEnvChanges()
print("local_hidden_url_validation=\(model.validationMessage ?? "none") effective_sensitive=\(model.effectiveSensitiveMode)")
'''
privacy_result = run('privacy_apply', [], privacy_main)

legacy_dir = scratch / 'legacy'
legacy_dir.mkdir(exist_ok=True)
for name in ['stt-record.sh', 'stt-runtime.sh']:
    shutil.copyfile(repo / name, legacy_dir / name)
(legacy_dir / 'legacy.pid').write_text('424242\n')
wrapper = r'''
set -eu
export STT_RUNTIME_DIR="$1/runtime" STT_LEGACY_PID_FILE="$1/legacy.pid" STT_LEGACY_RECORD_FILE="$1/legacy.wav" STT_KILL_LOG="$1/signals.log" STT_PROBE_FILE="$1/probe"
kill() {
 printf '%s\n' "$*" >> "$STT_KILL_LOG"
 if [[ "${1:-}" == "-0" ]]; then
  if [[ -f "$STT_PROBE_FILE" ]]; then return 1; fi
  touch "$STT_PROBE_FILE"
 fi
 return 0
}
export -f kill
bash "$1/stt-record.sh" cancel
cat "$STT_KILL_LOG"
'''
legacy_result = subprocess.run(['bash', '-c', wrapper, 'fixture', str(legacy_dir)], check=True, capture_output=True, text=True).stdout.strip()

result = {'release_commit': subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
          'env': env_result, 'sensitive_failure': runner_result, 'history': history_result,
          'privacy_apply': privacy_result, 'legacy_pid_signals_intercepted': legacy_result}
(out / 'reproductions.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
shutil.rmtree(scratch)
