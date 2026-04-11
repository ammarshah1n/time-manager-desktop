import Foundation
import Dependencies
import Supabase

/// Phase 10.01-10.03: Voice signal pipeline.
/// Extracts acoustic features via Gemini Audio API Edge Function.
/// Writes voice observations as Tier 0 for nightly pipeline processing.
/// Keeps SFSpeechRecognizer for interactive input; this handles background analysis.
actor VoiceFeatureService {
    static let shared = VoiceFeatureService()

    @Dependency(\.supabaseClient) private var supabaseClient

    struct VoiceFeatures: Sendable, Codable {
        let f0MeanHz: Double?
        let f0Variance: Double?
        let f0Contour: String?
        let jitterPercent: Double?
        let shimmerPercent: Double?
        let hnrDb: Double?
        let speechRateSyllablesPerSec: Double?
        let disfluencyRate: Double?
        let spectralCentroidHz: Double?
        let speakingTimeRatio: Double?
        let confidence: Double?
        let stressLevel: String?
        let fatigueIndicators: Bool?
        let engagementLevel: String?

        enum CodingKeys: String, CodingKey {
            case f0MeanHz = "f0_mean_hz"
            case f0Variance = "f0_variance"
            case f0Contour = "f0_contour"
            case jitterPercent = "jitter_percent"
            case shimmerPercent = "shimmer_percent"
            case hnrDb = "hnr_db"
            case speechRateSyllablesPerSec = "speech_rate_syllables_per_sec"
            case disfluencyRate = "disfluency_rate"
            case spectralCentroidHz = "spectral_centroid_hz"
            case speakingTimeRatio = "speaking_time_ratio"
            case confidence
            case stressLevel = "stress_level"
            case fatigueIndicators = "fatigue_indicators"
            case engagementLevel = "engagement_level"
        }
    }

    /// Extract voice features from audio data and record as Tier 0 observation (10.01, 10.03)
    func processAudioSegment(audioBase64: String, durationSeconds: Double) async {
        guard supabaseClient.rawClient != nil else { return }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return }

        do {
            // Call Gemini via Edge Function using URLSession
            guard let supabaseURL = ProcessInfo.processInfo.environment["SUPABASE_URL"],
                  let anonKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"],
                  let url = URL(string: "\(supabaseURL)/functions/v1/extract-voice-features")
            else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

            let payload: [String: Any] = [
                "executive_id": executiveId.uuidString,
                "audio_base64": audioBase64,
                "duration_seconds": durationSeconds,
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(VoiceFeatureResponse.self, from: data)
            guard let features = result.features else { return }

            // Write as Tier 0 observation (10.03)
            let observation = Tier0Observation(
                profileId: executiveId,
                occurredAt: Date(),
                source: .voice,
                eventType: "voice.acoustic_features",
                rawData: [
                    "f0_mean_hz": AnyCodable(features.f0MeanHz),
                    "speech_rate": AnyCodable(features.speechRateSyllablesPerSec),
                    "disfluency_rate": AnyCodable(features.disfluencyRate),
                    "stress_level": AnyCodable(features.stressLevel),
                    "speaking_time_ratio": AnyCodable(features.speakingTimeRatio),
                    "duration_seconds": AnyCodable(durationSeconds),
                    "confidence": AnyCodable(features.confidence),
                ]
            )
            try? await Tier0Writer.shared.recordObservation(observation)

            let dur = Int(durationSeconds)
            TimedLogger.dataStore.info("VoiceFeatureService: processed \(dur)s audio segment")
        } catch {
            TimedLogger.dataStore.error("VoiceFeatureService: extraction failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Response Type

    private struct VoiceFeatureResponse: Decodable, Sendable {
        let status: String?
        let features: VoiceFeatures?
    }
}
