import Foundation
import AVFoundation

/// Audio capture engine using AVAudioEngine with proper 16kHz PCM mono format for Whisper
class AudioEngine: NSObject, ObservableObject, AudioCaptureServiceProtocol {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioBuffer: Data = Data()
    private let bufferSize: UInt32 = 4096
    private let targetSampleRate: Double = 16000.0 // Whisper optimal sample rate
    private var converter: AVAudioConverter?
    
    var onAudioBuffer: ((Data) -> Void)?
    weak var audioLevelDelegate: AudioLevelDelegate?
    
    /// Accumulated audio data for the current recording session
    private var recordedAudioData: Data = Data()
    
    override init() {
        super.init()
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine?.inputNode
    }
    
    /// Request microphone permission
    func requestPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    /// Start recording audio with 16kHz PCM mono format
    func startRecording() {
        guard !isRecording else { return }
        
        // Reset recorded data
        recordedAudioData = Data()
        
        audioEngine = AVAudioEngine()
        guard let inputNode = audioEngine?.inputNode else {
            print("Failed to get input node")
            return
        }
        
        // Get the native input format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Create target format: 16kHz, mono, 16-bit PCM
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            print("Failed to create target audio format")
            return
        }
        
        // Create converter if input format differs from target
        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, inputFormat: inputFormat, targetFormat: targetFormat)
        }
        
        audioEngine?.prepare()
        
        do {
            try audioEngine?.start()
            DispatchQueue.main.async {
                self.isRecording = true
            }
            print("Audio recording started at 16kHz PCM mono")
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    /// Stop recording audio and return accumulated data as WAV
    func stopRecording() -> Data? {
        guard isRecording else { return nil }
        
        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
        converter = nil
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0.0
        }
        
        print("Audio recording stopped, captured \(recordedAudioData.count) bytes")
        
        // Convert raw PCM to WAV format for Whisper API
        let wavData = createWAVFile(from: recordedAudioData)
        recordedAudioData.removeAll()
        
        return wavData
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat, targetFormat: AVAudioFormat) {
        // Calculate audio level from the buffer
        calculateAudioLevel(buffer)
        
        // Convert buffer to target format (16kHz, mono, Int16)
        if let convertedBuffer = convertBuffer(buffer, to: targetFormat) {
            // Extract Int16 data
            let channelData = convertedBuffer.int16ChannelData![0]
            let frameLength = Int(convertedBuffer.frameLength)
            let data = Data(bytes: channelData, count: frameLength * MemoryLayout<Int16>.size)
            
            recordedAudioData.append(data)
            
            // Stream buffer for real-time processing if needed
            DispatchQueue.main.async { [weak self] in
                self?.onAudioBuffer?(data)
            }
        }
    }
    
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        // If no conversion needed, extract data directly
        if buffer.format.sampleRate == targetSampleRate && buffer.format.channelCount == 1 {
            return buffer
        }
        
        guard let converter = self.converter else { return nil }
        
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return nil
        }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if status == .error || error != nil {
            print("Conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }
        
        return outputBuffer
    }
    
    private func calculateAudioLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        
        // Calculate RMS
        let sum = samples.map { $0 * $0 }.reduce(0, +)
        let rms = sqrt(sum / Float(frameLength))
        
        // Normalize with logarithmic scaling for better visualization
        let db = 20 * log10(max(rms, 0.00001))
        let normalizedLevel = min(max((db + 60) / 60, 0), 1) // Map -60dB to 0dB range
        
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = normalizedLevel
            self?.audioLevelDelegate?.audioLevelDidChange(normalizedLevel)
        }
    }
    
    /// Create WAV file header and data for Whisper API
    private func createWAVFile(from pcmData: Data) -> Data {
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let totalSize = dataSize + 36
        
        var wavData = Data()
        
        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: totalSize.littleEndian, Data.init))
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian, Data.init)) // Subchunk1Size
        wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian, Data.init))  // AudioFormat (PCM)
        wavData.append(withUnsafeBytes(of: channels.littleEndian, Data.init))
        wavData.append(withUnsafeBytes(of: sampleRate.littleEndian, Data.init))
        wavData.append(withUnsafeBytes(of: byteRate.littleEndian, Data.init))
        wavData.append(withUnsafeBytes(of: blockAlign.littleEndian, Data.init))
        wavData.append(withUnsafeBytes(of: bitsPerSample.littleEndian, Data.init))
        
        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: dataSize.littleEndian, Data.init))
        wavData.append(pcmData)
        
        return wavData
    }
}

// MARK: - Data Extensions

extension Data {
    mutating func append(_ other: Data) {
        self.append(contentsOf: other)
    }
}
