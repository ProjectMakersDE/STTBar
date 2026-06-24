import AppKit
import SwiftUI

final class StatusWindow {
    private var window: NSWindow?
    private let model: HealthCenterModel

    init(model: HealthCenterModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: StatusView(model: model))
            let w = NSWindow(contentViewController: host)
            w.title = L("STTBar - Status & Diagnose", "STTBar - Status & diagnostics")
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 760, height: 560))
            window = w
        }
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct StatusView: View {
    @ObservedObject var model: HealthCenterModel
    @ObservedObject private var loc = Localization.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(L("Aktualisieren", "Refresh")) { model.refresh() }
                Button(L("Whisper testen", "Test Whisper")) { model.testWhisper() }
                Button(L("LM Studio testen", "Test LM Studio")) { model.testLMStudio() }
                Button(L("Mikrofon-Test", "Microphone test")) { model.microphoneTest() }
                Button(L("Testtext einfügen", "Insert test text")) { model.clipboardTest() }
                Button(L("Server vorwärmen", "Warm up servers")) { model.prewarmServers() }
                Spacer()
                Button(L("Bericht kopieren", "Copy report")) { model.copyReport() }
            }
            if let message = model.actionMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            List(model.checks) { check in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: icon(for: check.level))
                        .foregroundStyle(color(for: check.level))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.title)
                        Text(check.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 260)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Letztes Problem", "Last problem")).font(.headline)
                    Text(problemText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Letzte Läufe", "Recent runs")).font(.headline)
                    ForEach(model.metrics.prefix(5)) { metric in
                        Text(metricLine(metric)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }

    private var problemText: String {
        guard let p = model.lastProblem else { return L("Kein Fehler protokolliert", "No error logged") }
        return "\(p.severity.uppercased()) \(p.event): \(p.message) \(p.detail ?? "")"
    }

    private func icon(for level: HealthCheckItem.Level) -> String {
        switch level {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func color(for level: HealthCheckItem.Level) -> Color {
        switch level {
        case .ok: return .green
        case .warning: return .orange
        case .error: return .red
        case .unknown: return .secondary
        }
    }

    private func metricLine(_ m: RunMetric) -> String {
        let whisper = Double(m.whisperMs ?? 0) / 1000
        let llm = Double(m.postprocessMs ?? 0) / 1000
        return "\(m.mode ?? "?"): Whisper \(String(format: "%.1f", whisper))s, LLM \(String(format: "%.1f", llm))s, Paste \(m.pasteStatus ?? "?")"
    }
}
