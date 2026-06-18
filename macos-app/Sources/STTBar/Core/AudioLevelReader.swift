import Foundation

/// Computes per-bucket audio levels from the tail of a 16-bit PCM wav file.
/// Stateless w.r.t. smoothing — the caller (HUD) applies temporal smoothing.
struct AudioLevelReader {
    let bucketCount: Int
    private let headerBytes = 44
    // Keep the HUD responsive by sampling only the newest ~100-120 ms.
    // Larger windows look delayed during live dictation.
    private let bytesPerBucketTarget = 160

    func levels(from url: URL) -> [Double] {
        let zeros = Array(repeating: 0.0, count: bucketCount)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return zeros }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > UInt64(headerBytes) else { return zeros }
        let available = Int(size) - headerBytes
        var readBytes = min(available, bucketCount * bytesPerBucketTarget)
        readBytes -= readBytes % 2
        guard readBytes > 0 else { return zeros }
        try? handle.seek(toOffset: size - UInt64(readBytes))
        guard let data = try? handle.read(upToCount: readBytes), !data.isEmpty else { return zeros }

        let sampleCount = data.count / 2
        guard sampleCount > 0 else { return zeros }
        let samples: [Int16] = data.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: Int16.self)
            return (0..<sampleCount).map { Int16(littleEndian: buf[$0]) }
        }
        let per = max(1, sampleCount / bucketCount)
        var out = zeros
        for b in 0..<bucketCount {
            let start = b * per
            let end = (b == bucketCount - 1) ? sampleCount : min(sampleCount, (b + 1) * per)
            if start >= end { continue }
            var sumSq = 0.0, peak = 0.0, n = 0.0
            for i in start..<end {
                let norm = abs(Double(samples[i])) / 32768.0
                peak = max(peak, norm); sumSq += norm * norm; n += 1
            }
            let rms = n > 0 ? (sumSq / n).squareRoot() : 0
            let voice = max(rms * 1.45, peak * 0.46)
            let gated = max(0, voice - 0.003)
            out[b] = min(1, pow(gated * 31.0, 0.52))
        }
        return out
    }
}
