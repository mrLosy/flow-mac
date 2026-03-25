# macOS App Sandbox Guidelines

## Обязательные Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Sandbox обязателен для App Store -->
    <key>com.apple.security.app-sandbox</key>
    <true/>
    
    <!-- Network для Whisper API -->
    <key>com.apple.security.network.client</key>
    <true/>
    
    <!-- Microphone access -->
    <key>com.apple.security.device.microphone</key>
    <true/>
    
    <!-- File access только для temporary files -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

## Info.plist Permissions

```xml
<!-- Microphone permission description -->
<key>NSMicrophoneUsageDescription</key>
<string>Flow Mac needs microphone access to transcribe your voice into text.</string>

<!-- Accessibility permission description -->
<key>NSAccessibilityUsageDescription</key>
<string>Flow Mac needs accessibility access to insert transcribed text into the active text field.</string>
```

## Security Best Practices

### API Key Storage

```swift
// ✅ UserDefaults для development
@AppStorage("whisperAPIKey") private var apiKey: String = ""

// ✅ Keychain для production
import Security

func saveAPIKey(_ key: String) throws {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: "whisperAPIKey",
        kSecValueData as String: key.data(using: .utf8)!,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    
    SecItemDelete(query as CFDictionary)
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw KeychainError.saveFailed
    }
}
```

### Network Security

```swift
// ✅ HTTPS only
let config = URLSessionConfiguration.default
config.httpShouldUsePipelining = false

// ✅ API key в header
request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

// ❌ Никогда не логировать API key
// logger.debug("API Key: \(apiKey)") // ЗАПРЕЩЕНО
```

### File Access

```swift
// ✅ Использовать только temporary directory
let tempDir = FileManager.default.temporaryDirectory
let audioFile = tempDir.appendingPathComponent("recording.wav")

// ✅ Автоматическая очистка
defer {
    try? FileManager.default.removeItem(at: audioFile)
}
```

## Code Signing

```bash
# Development
CODE_SIGN_IDENTITY="Apple Development"

# Distribution
CODE_SIGN_IDENTITY="Apple Distribution"

# Notarization (required for distribution outside App Store)
xcrun altool --notarize-app \
    --primary-bundle-id "com.flowmac.app" \
    --username "$APPLE_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --file FlowMac.app
```
