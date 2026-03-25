# Swift Coding Standards

## Обязательные правила

### Синтаксис

```swift
// ✅ Всегда использовать self
self.audioEngine.startRecording()

// ❌ Нельзя опускать self
audioEngine.startRecording()
```

### Optionals

```swift
// ✅ Guard для early return
guard let apiKey = self.apiKey else {
    self.showError("API key required")
    return
}

// ✅ If let для опциональных значений
if let result = try? await service.recognize(audioData) {
    self.handleResult(result)
}

// ❌ Никаких force unwrap
let value = someOptional! // ЗАПРЕЩЕНО
```

### Error Handling

```swift
// ✅ Обрабатывать ошибки явно
do {
    try await self.recognitionService.transcribe(audioData)
} catch let error as RecognitionError {
    self.logger.error("Recognition failed: \(error)")
    self.showError(error.localizedDescription)
} catch {
    self.logger.error("Unknown error: \(error)")
}

// ❌ Не игнорировать ошибки
// try? service.call() // Только если ошибка не важна
```

### Concurrency

```swift
// ✅ @MainActor для UI updates
@MainActor
func updateUI(with text: String) {
    self.textView.string = text
}

// ✅ @Sendable для closures
Task { @Sendable in
    await self.processAudio()
}

// ✅ Async/await вместо completion handlers
func fetchData() async throws -> Data {
    // Implementation
}
```

## macOS-Specific

### AVAudioEngine

```swift
// ✅ Правильная настройка audio session
self.audioEngine = AVAudioEngine()
guard let inputNode = self.audioEngine.inputNode else {
    throw AudioError.noInputDevice
}

let format = inputNode.outputFormat(forBus: 0)
inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
    // Process buffer
}
```

### Carbon Hotkeys

```swift
// ✅ Регистрация hotkey с обработкой ошибок
guard RegisterEventHotKey(
    UInt32(kVK_Space),
    UInt32(cmdKey | shiftKey),
    hotKeyID,
    GetEventDispatcherTarget(),
    0,
    &hotKeyRef
) == noErr else {
    throw HotkeyError.registrationFailed
}
```

### Text Injection

```swift
// ✅ Accessibility API
let systemWideAX = AXUIElementCreateSystemWide()
var focusedElement: AXUIElement?
AXUIElementCopyAttributeValue(
    systemWideAX,
    kAXFocusedUIElementAttribute as CFString,
    &focusedElement
)
```

## Архитектура

### Protocol-Oriented Design

```swift
// ✅ Протокол с associated type
protocol AudioCaptureServiceProtocol: AnyObject {
    var isRecording: Bool { get }
    var audioDataPublisher: AnyPublisher<Data, Error> { get }
    
    func startRecording() throws
    func stopRecording()
}

// ✅ Реализация
final class AudioEngine: NSObject, AudioCaptureServiceProtocol {
    // Implementation
}
```

### Dependency Injection

```swift
// ✅ Constructor injection
final class RecordingViewModel: ObservableObject {
    private let audioService: AudioCaptureServiceProtocol
    private let recognitionService: WhisperRecognitionServiceProtocol
    
    init(
        audioService: AudioCaptureServiceProtocol,
        recognitionService: WhisperRecognitionServiceProtocol
    ) {
        self.audioService = audioService
        self.recognitionService = recognitionService
    }
}
```

## SwiftUI

### View Structure

```swift
// ✅ Разделение на small views
struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    
    var body: some View {
        Form {
            APIKeySection(viewModel: viewModel)
            LanguageSection(viewModel: viewModel)
            ShortcutSection(viewModel: viewModel)
        }
    }
}

// ✅ Separate section view
private struct APIKeySection: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        Section("API Key") {
            SecureField("OpenAI API Key", text: $viewModel.apiKey)
        }
    }
}
```

### State Management

```swift
// ✅ @StateObject для owned objects
@StateObject private var viewModel = RecordingViewModel()

// ✅ @ObservedObject для injected objects
@ObservedObject var viewModel: RecordingViewModel

// ✅ @AppStorage для настроек
@AppStorage("showOverlay") private var showOverlay = true
```

## Документирование

```swift
/// Starts audio recording from the default input device
/// - Throws: `AudioError.noInputDevice` if microphone is not available
/// - Throws: `AudioError.permissionDenied` if microphone access is denied
func startRecording() throws

/// Injects text into the currently focused text field
/// - Parameter text: The text to inject
/// - Returns: `true` if injection was successful
/// - Note: Requires Accessibility permissions
@discardableResult
func injectText(_ text: String) -> Bool
```
