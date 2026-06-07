import FluidAudio
import Foundation
import Logging

final class KokoroTTSService: TTSService, @unchecked Sendable {
    let sampleRate: Int = KokoroAneConstants.sampleRate
    private(set) var defaultVoice: String = KokoroAneConstants.defaultVoice
    let availableVoices: [String] = KokoroTTSService.englishVoices.sorted()

    /// English-variant Kokoro voices from the `FluidInference/kokoro-82m-coreml` voice pack:
    /// American (`af_`/`am_`) and British (`bf_`/`bm_`). FluidAudio's KokoroAne `.english`
    /// variant uses an English G2P pipeline, so only these voices are exposed (other-language
    /// packs need their own G2P and are not supported here). American voices are production
    /// quality. The Kokoro engine no longer ships an enumerable voice list, so it is pinned here.
    static let englishVoices: [String] = [
        "af_alloy", "af_aoede", "af_bella", "af_heart", "af_jessica", "af_kore",
        "af_nicole", "af_nova", "af_river", "af_sarah", "af_sky",
        "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam", "am_michael",
        "am_onyx", "am_puck", "am_santa",
        "bf_alice", "bf_emma", "bf_isabella", "bf_lily",
        "bm_daniel", "bm_fable", "bm_george", "bm_lewis",
    ]

    private var manager: KokoroAneManager?
    private var logger: Logger = {
        var l = Logger(label: "KokoroTTSService")
        l.logLevel = .notice
        return l
    }()

    func initialize(settings: KokoroSettings = KokoroSettings()) async throws {
        let voiceId = settings.defaultVoice ?? KokoroAneConstants.defaultVoice
        let m = KokoroAneManager(variant: .english, defaultVoice: voiceId)
        try await m.initialize()
        self.manager = m
        self.defaultVoice = voiceId
    }

    // Returns a complete WAV file produced directly by KokoroAneManager.synthesize().
    func synthesize(text: String, voice: String) async throws -> Data {
        guard let manager = manager else {
            throw KokoroTTSError.notInitialized
        }
        guard availableVoices.contains(voice) else {
            throw KokoroTTSError.voiceNotFound(voice)
        }
        logger.notice("Kokoro synthesize: \(text.prefix(80))...")
        let data = try await manager.synthesize(text: text, voice: voice)
        logger.notice("Kokoro synthesis done: \(data.count) bytes")
        return data
    }

    // Yields raw 16-bit little-endian PCM (24 kHz mono, no WAV header) one chunk per
    // sentence. The Float32 samples for a sentence (KokoroAneSynthesisResult.samples) are
    // peak-normalised once and converted to PCM16.
    func synthesizeStream(text: String, voice: String) -> AsyncThrowingStream<Data, Error> {
        guard availableVoices.contains(voice) else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: KokoroTTSError.voiceNotFound(voice))
            }
        }

        let sentences = detectSentences(text)
        logger.notice("Kokoro synthesizeStream: \(sentences.count) sentence(s)")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let manager = self.manager else {
                        throw KokoroTTSError.notInitialized
                    }
                    for sentence in sentences {
                        let result = try await manager.synthesizeDetailed(
                            text: sentence, voice: voice)
                        if !result.samples.isEmpty {
                            continuation.yield(float32ToPCM16(result.samples))
                        }
                    }
                    continuation.finish()
                }
                catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Errors

enum KokoroTTSError: Error, CustomStringConvertible {
    case notInitialized
    case voiceNotFound(String)

    var description: String {
        switch self {
        case .notInitialized:
            return "Kokoro TTS service has not been initialized."
        case .voiceNotFound(let voice):
            return "Voice '\(voice)' is not available. Use a Kokoro voice ID (e.g. 'af_heart', 'am_adam')."
        }
    }
}
