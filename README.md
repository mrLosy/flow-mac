# Flow Mac 🎙️

AI-powered voice dictation for macOS using OpenAI Whisper API.

[![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-15.0+-blue.svg)](https://developer.apple.com/xcode)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Features ✨

- 🎤 **Voice Dictation** - Press a hotkey, speak, and text appears
- 🤖 **AI-Powered** - Uses OpenAI Whisper API for accurate transcription
- ⚡ **Global Hotkey** - Works from anywhere with customizable shortcut
- 📝 **Text Injection** - Automatically inserts text into active text fields
- 🎨 **Native macOS** - SwiftUI interface with menu bar integration
- 🔒 **Privacy First** - No audio stored locally, sent directly to OpenAI API
- 🌐 **Multi-language** - Supports 99+ languages via Whisper

## Installation 📦

### Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0+ (for building from source)
- OpenAI API key ([get one here](https://platform.openai.com/api-keys))

### Build from Source

```bash
# Clone the repository
git clone https://github.com/flowmac/flow-mac.git
cd flow-mac

# Build with Xcode
xcodebuild -project FlowMac.xcodeproj \
    -scheme FlowMac \
    -configuration Release \
    -derivedDataPath build \
    clean build

# Or use the build script
./build.sh
```

The built app will be at `build/Build/Products/Release/FlowMac.app`

### Install

1. Copy `FlowMac.app` to your `/Applications` folder
2. Launch the app
3. Grant required permissions when prompted:
   - **Microphone** - for voice recording
   - **Accessibility** - for text injection
   - **Input Monitoring** - for global hotkeys

## Usage 🚀

### Getting Started

1. **Launch Flow Mac** - The app runs in the menu bar (waveform icon)
2. **Set API Key** - Open Settings (Cmd+,) and enter your OpenAI API key
3. **Grant Permissions** - Allow microphone and accessibility access
4. **Start Dictating** - Press `Cmd+Shift+Space`, speak, then press again to stop

### Default Hotkey

- **Start/Stop Recording**: `Cmd + Shift + Space`

### Customization

- Change hotkey in Settings → Shortcuts
- Select recognition language in Settings → General
- Enable/disable recording overlay in Settings

## Architecture 🏗️

```
FlowMac/
├── App/                          # Entry point
│   ├── FlowMacApp.swift         # @main app structure
│   └── AppDelegate.swift        # Lifecycle events
│
├── Core/                         # Core services
│   ├── Audio/                   # Audio capture
│   │   ├── AudioCaptureServiceProtocol.swift
│   │   └── AudioEngine.swift    # AVAudioEngine implementation
│   │
│   ├── Recognition/             # Speech recognition
│   │   ├── WhisperRecognitionServiceProtocol.swift
│   │   └── RecognitionService.swift  # OpenAI API client
│   │
│   ├── Injection/               # Text injection
│   │   ├── TextInjectionServiceProtocol.swift
│   │   └── TextInjector.swift   # CGEvent + Accessibility
│   │
│   └── Hotkey/                  # Global hotkeys
│       ├── HotkeyManagerProtocol.swift
│       └── HotkeyManager.swift  # Carbon EventTap
│
├── Features/                     # UI components
│   ├── Recording/               # Recording UI
│   │   ├── StatusBarController.swift
│   │   ├── StatusBarMenuView.swift
│   │   └── RecordingOverlay.swift
│   │
│   └── Settings/                # Settings window
│       ├── SettingsWindow.swift
│       └── SettingsView.swift
│
└── Resources/                    # Assets and configs
    ├── FlowMac.entitlements     # Sandbox permissions
    └── Info.plist              # App configuration
```

## Data Flow 🔄

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Hotkey     │────▶│   Recording  │────▶│   Audio     │
│  (Cmd+Shift+│     │   Started    │     │   Buffer    │
│   Space)    │     └──────────────┘     └──────┬──────┘
└─────────────┘                                 │
                                                ▼
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Result     │◀────│  Text        │◀────│  Whisper    │
│  Inserted   │     │  Injection   │     │  API        │
└─────────────┘     └──────────────┘     └─────────────┘
```

## Technical Details 🔧

### Audio Engine

- **Framework**: AVAudioEngine
- **Format**: 16kHz, 16-bit PCM, Mono
- **Buffer**: 4096 samples (real-time processing)
- **Output**: WAV format for Whisper API

### Whisper API

- **Endpoint**: `https://api.openai.com/v1/audio/transcriptions`
- **Model**: whisper-1
- **Language**: Auto-detect or user-specified
- **Retry Logic**: 3 attempts with exponential backoff

### Text Injection

Three methods (fallback chain):
1. **Accessibility API** - Most reliable for native apps
2. **CGEvent Unicode** - Universal Unicode support
3. **Pasteboard** - Works everywhere, preserves clipboard

### Hotkey System

- **Primary**: Carbon RegisterEventHotKey
- **Fallback**: CGEventTap
- **Default**: Cmd+Shift+Space
- **Configurable**: Any key + modifier combination

## Permissions 🔐

| Permission | Purpose | Required |
|------------|---------|----------|
| Microphone | Capture voice input | ✅ Yes |
| Accessibility | Inject text into apps | ✅ Yes |
| Input Monitoring | Global hotkey detection | ✅ Yes |
| Network | Connect to OpenAI API | ✅ Yes |

## Testing 🧪

```bash
# Run all tests
xcodebuild test -project FlowMac.xcodeproj -scheme FlowMac

# Run specific test target
xcodebuild test -project FlowMac.xcodeproj \
    -scheme FlowMac \
    -only-testing:FlowMacTests
```

### Test Coverage

- ✅ AudioEngine - recording, format conversion, WAV generation
- ✅ RecognitionService - API calls, error handling, retries
- ✅ TextInjector - accessibility, CGEvent, pasteboard
- ✅ HotkeyManager - hotkey registration, event handling
- ✅ Integration - full workflow tests

## Configuration ⚙️

### UserDefaults Keys

| Key | Type | Description |
|-----|------|-------------|
| `whisperAPIKey` | String | OpenAI API key |
| `recognitionLanguage` | String | Language code (e.g., "en", "ru") |
| `hotkeyKeyCode` | UInt32 | Virtual key code |
| `hotkeyModifiers` | UInt32 | Modifier flags |
| `showRecordingOverlay` | Bool | Show/hide overlay |
| `playSounds` | Bool | Enable sound effects |

## Troubleshooting 🐛

### "No microphone access"

1. Open System Settings → Privacy & Security → Microphone
2. Enable Flow Mac
3. Restart the app

### "Text not inserting"

1. Open System Settings → Privacy & Security → Accessibility
2. Enable Flow Mac
3. Restart the app

### "Hotkey not working"

1. Open System Settings → Privacy & Security → Input Monitoring
2. Enable Flow Mac
3. Restart the app

### "API Error"

- Verify your API key is correct
- Check your OpenAI account has available credits
- Check internet connection

## Roadmap 🗺️

- [ ] Real-time streaming transcription
- [ ] Local Whisper model support
- [ ] Custom vocabulary/prompts
- [ ] Voice commands (punctuation, editing)
- [ ] Multiple transcription providers
- [ ] Keyboard shortcut customization UI
- [ ] Audio device selection
- [ ] Recording history

## Contributing 🤝

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) first.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License 📄

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments 🙏

- [OpenAI Whisper](https://openai.com/research/whisper) - Speech recognition model
- [Apple Developer Documentation](https://developer.apple.com/documentation) - AVFoundation, Carbon, SwiftUI

## Support 💬

- [GitHub Issues](https://github.com/flowmac/flow-mac/issues) - Bug reports and feature requests
- [Discussions](https://github.com/flowmac/flow-mac/discussions) - Questions and ideas

---

<p align="center">Made with ❤️ for macOS users</p>
