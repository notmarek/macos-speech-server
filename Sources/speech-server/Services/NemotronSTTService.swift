import FluidAudio
import Foundation
import Logging

/// STT service backed by FluidAudio's `StreamingNemotronMultilingualAsrManager`
/// (NVIDIA Nemotron multilingual streaming ASR, ~40 languages).
///
/// Unlike the batch engines (`FluidSTTService`, `Qwen3STTService`), the Nemotron manager is a
/// *stateful streaming actor*: audio is fed via `process(samples:)`, the final transcript is
/// retrieved with `finish()`, and `reset()` clears state between utterances. The manager also
/// gates speech internally, so this service does **not** run a separate VAD segmentation pass.
///
/// This service is itself an `actor`, which serializes concurrent `transcribe(audioURL:)` calls.
/// Serialization is required: a single streaming manager cannot interleave two transcriptions
/// without corrupting its encoder/decoder state.
@available(macOS 15, *)
actor NemotronSTTService: STTService {
    private var manager: StreamingNemotronMultilingualAsrManager?
    private let language: String?
    private let logger: Logger = {
        var l = Logger(label: "NemotronSTTService")
        l.logLevel = .notice
        return l
    }()

    init(language: String?) {
        self.language = language
    }

    func initialize(chunkMs: Int) async throws {
        let langCode = language ?? "auto"
        let modelDir = try await StreamingNemotronMultilingualAsrManager.downloadVariant(
            languageCode: langCode, chunkMs: chunkMs
        )
        let mgr = StreamingNemotronMultilingualAsrManager()
        try await mgr.loadModels(from: modelDir)
        self.manager = mgr
    }

    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        guard let manager else {
            throw NemotronSTTError.notInitialized
        }

        logger.notice("Transcribing (Nemotron): \(audioURL.lastPathComponent)")

        let diskSource: DiskBackedAudioSampleSource
        do {
            let factory = AudioSourceFactory()
            let (source, _) = try factory.makeDiskBackedSource(
                from: audioURL, targetSampleRate: 16000
            )
            diskSource = source
        }
        catch {
            throw NemotronSTTError.audioConversionFailed(error)
        }
        defer { diskSource.cleanup() }

        let totalSamples = diskSource.sampleCount
        let totalDuration = Double(totalSamples) / 16000.0

        guard totalSamples > 160 else {
            throw NemotronSTTError.audioTooShort
        }

        // Reset streaming state from any prior transcription, then apply the language hint.
        await manager.reset()
        if let language {
            await manager.setLanguage(language)
        }

        // Feed the file in fixed blocks. The manager handles its own chunking/VAD gating; we only
        // need to bound peak RAM, so 30-second blocks (480k samples) are plenty.
        let blockSize = 30 * 16_000
        var block = [Float](repeating: 0, count: blockSize)
        for offset in stride(from: 0, to: totalSamples, by: blockSize) {
            let count = min(blockSize, totalSamples - offset)
            try diskSource.copySamples(into: &block, offset: offset, count: count)
            let samples = count == blockSize ? block : Array(block[..<count])
            _ = try await manager.process(samples: samples)
        }

        let text = try await manager.finish().trimmingCharacters(in: .whitespacesAndNewlines)

        let segments: [SegmentResult] =
            text.isEmpty
            ? []
            : [SegmentResult(text: text, start: 0, end: totalDuration.rounded3, words: [], confidence: 1.0)]

        logger.notice("Transcription done (Nemotron): duration=\(totalDuration)s")
        logger.debug("Transcription text: '\(text)'")

        return TranscriptionResult(text: text, duration: totalDuration, words: [], segments: segments)
    }
}

extension Double {
    fileprivate var rounded3: Double { (self * 1000).rounded() / 1000 }
}

enum NemotronSTTError: Error, CustomStringConvertible {
    case notInitialized
    case audioConversionFailed(Error)
    case audioTooShort
    case unsupportedPlatform

    var description: String {
        switch self {
        case .notInitialized:
            return "Nemotron ASR service has not been initialized."
        case .audioConversionFailed(let underlying):
            return "Audio conversion failed: \(underlying)"
        case .audioTooShort:
            return "Audio file is too short to transcribe."
        case .unsupportedPlatform:
            return "Nemotron ASR requires macOS 15 or later."
        }
    }
}
