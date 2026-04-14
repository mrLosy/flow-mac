import Foundation

enum AudioValidationError: Error, LocalizedError {
    case tooSmall
    case invalidHeader
    case noAudioData
    case silentRecording

    var errorDescription: String? {
        switch self {
        case .tooSmall: return "Audio recording too short"
        case .invalidHeader: return "Invalid audio format"
        case .noAudioData: return "No audio data in recording"
        case .silentRecording: return "No speech detected (silent recording)"
        }
    }
}

enum AudioValidator {
    /// Validate WAV audio data before sending to API
    static func validate(_ data: Data) -> Result<Void, AudioValidationError> {
        // WAV header is 44 bytes minimum
        guard data.count > 44 else { return .failure(.tooSmall) }

        // Check RIFF header
        let riff = data[0..<4]
        guard String(data: riff, encoding: .ascii) == "RIFF" else { return .failure(.invalidHeader) }

        // Check WAVE marker
        let wave = data[8..<12]
        guard String(data: wave, encoding: .ascii) == "WAVE" else { return .failure(.invalidHeader) }

        // Check data chunk has content (after 44-byte header)
        let audioPayload = data.count - 44
        guard audioPayload > 0 else { return .failure(.noAudioData) }

        // Check for silence: if all samples are zero or near-zero
        if audioPayload > 100 {
            let samples = data.suffix(from: 44)
            var sumSquared: Float = 0
            let sampleCount = audioPayload / 2 // Int16 samples
            guard sampleCount > 0 else { return .failure(.noAudioData) }

            samples.withUnsafeBytes { rawBuffer in
                let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
                for i in 0..<min(sampleCount, int16Buffer.count) {
                    let sample = Float(int16Buffer[i]) / Float(Int16.max)
                    sumSquared += sample * sample
                }
            }

            let rms = sqrt(sumSquared / Float(sampleCount))
            // If RMS is below -50dB, consider it silent
            if rms < 0.003 {
                return .failure(.silentRecording)
            }
        }

        return .success(())
    }
}
