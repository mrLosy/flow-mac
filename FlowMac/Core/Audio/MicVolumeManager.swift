import Foundation
import CoreAudio

/// Manages microphone volume: auto-boost to 100% before recording, restore after
final class MicVolumeManager {
    static let shared = MicVolumeManager()

    private var originalVolume: Float?
    private var deviceID: AudioDeviceID = 0

    private init() {}

    /// Boost microphone input volume to 100% if enabled in settings
    func boostIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "autoBoostMicVolume") else { return }
        boost()
    }

    /// Restore original microphone volume
    func restoreIfNeeded() {
        guard originalVolume != nil else { return }
        restore()
    }

    private func boost() {
        guard let inputDevice = defaultInputDevice() else { return }
        deviceID = inputDevice

        // Save original volume
        originalVolume = getVolume(device: inputDevice)
        guard originalVolume != nil else { return }

        // Set to 100%
        setVolume(device: inputDevice, volume: 1.0)
        NSLog("[FlowMac] Mic volume boosted from \(originalVolume!) to 1.0")
    }

    private func restore() {
        guard let original = originalVolume else { return }
        setVolume(device: deviceID, volume: original)
        NSLog("[FlowMac] Mic volume restored to \(original)")
        originalVolume = nil
    }

    private func defaultInputDevice() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &propSize, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private func getVolume(device: AudioDeviceID) -> Float? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        // Check if property exists on element 0, otherwise try element 1
        if !AudioObjectHasProperty(device, &addr) {
            addr.mElement = 1
            guard AudioObjectHasProperty(device, &addr) else { return nil }
        }

        var volume: Float32 = 0
        var propSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &propSize, &volume)
        guard status == noErr else { return nil }
        return volume
    }

    private func setVolume(device: AudioDeviceID, volume: Float) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        if !AudioObjectHasProperty(device, &addr) {
            addr.mElement = 1
            guard AudioObjectHasProperty(device, &addr) else { return }
        }

        var mutableVolume = volume
        let propSize = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &addr, 0, nil, propSize, &mutableVolume)
    }

    deinit {
        restoreIfNeeded()
    }
}
