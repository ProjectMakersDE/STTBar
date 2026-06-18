import Foundation

final class ServerWarmer {
    private var timer: Timer?
    private weak var model: SettingsModel?

    init(model: SettingsModel) {
        self.model = model
    }

    func reload() {
        timer?.invalidate()
        guard AppSettings.shared.prewarmEnabled,
              AppSettings.shared.keepModelWarmSeconds > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(AppSettings.shared.keepModelWarmSeconds), repeats: true) { [weak self] _ in
            self?.ping()
        }
    }

    func ping() {
        guard let model else { return }
        for raw in [model.whisperURL, model.postprocessEnabled ? model.lmStudioURL : ""].filter({ !$0.isEmpty }) {
            guard let url = URL(string: raw) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            URLSession.shared.dataTask(with: request) { _, _, _ in
                AppLogger.log("server_warm_ping url=\(url.host ?? "unknown")")
            }.resume()
        }
    }
}
