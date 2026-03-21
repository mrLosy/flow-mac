# Flow Mac

Voice dictation app for macOS powered by OpenAI Whisper.

## Overview

Flow Mac is a macOS menu bar application that provides voice-to-text dictation using OpenAI's Whisper API. It features:

- 🎙️ Global hotkey activation (default: Option + Space)
- 🔊 Real-time audio level visualization
- 📝 Automatic text injection into any application
- ⚙️ Configurable settings
- 🔒 Privacy-focused (audio processed via OpenAI API)

## Requirements

- macOS 13.0+
- Xcode 15.0+ (for building)
- OpenAI API key

## Architecture

```
FlowMac/
├── App/
│   ├── FlowMacApp.swift          # App entry point
│   └── AppDelegate.swift         # Lifecycle and service initialization
├── Core/
│   ├── Audio/
│   │   ├── AudioEngine.swift                    # Audio capture implementation
│   │   └── AudioCaptureServiceProtocol.swift    # Audio protocol
│   ├── Recognition/
│   │   ├── RecognitionService.swift             # Whisper API client
│   │   └── WhisperRecognitionServiceProtocol.swift
│   ├── Injection/
│   │   ├── TextInjector.swift                   # Text insertion
│   │   └── TextInjectionServiceProtocol.swift
│   └── Hotkey/
│       ├── HotkeyManager.swift                  # Global hotkey handling
│       └── HotkeyManagerProtocol.swift
├── Features/
│   ├── Recording/
│   │   ├── StatusBarController.swift    # Menu bar UI
│   │   ├── StatusBarMenuView.swift      # Menu bar SwiftUI
│   │   └── RecordingOverlay.swift       # Recording visual feedback
│   └── Settings/
│       └── SettingsWindow.swift         # Settings UI
└── Resources/
    ├── Info.plist
    └── FlowMac.entitlements
```

## Building

### Using Xcode

1. Open `FlowMac.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run (⌘+R)

### Using Command Line

```bash
# Build with build script
./build.sh

# Or build directly with xcodebuild
xcodebuild -project FlowMac.xcodeproj -scheme FlowMac -configuration Release build
```

### Using Swift Package Manager

```bash
swift build -c release
```

## Setup

1. **Get an OpenAI API Key**
   - Visit [OpenAI Platform](https://platform.openai.com/api-keys)
   - Create a new API key

2. **Grant Permissions**
   - **Microphone**: Required for voice capture
   - **Accessibility**: Required for text insertion into other apps
   - **Input Monitoring**: Required for global hotkey detection

3. **Configure Settings**
   - Open Settings from the menu bar
   - Enter your OpenAI API key
   - Customize hotkey if desired

## Usage

1. Click the Flow Mac icon in the menu bar or press `Option + Space`
2. Speak clearly into your microphone
3. Press the hotkey again or click Stop
4. Transcribed text will be inserted at the cursor position

## Permissions

Flow Mac requires the following permissions:

| Permission | Purpose |
|------------|---------|
| Microphone | Capture voice audio for transcription |
| Accessibility | Insert transcribed text into other applications |
| Input Monitoring | Detect global hotkey events |

## Security & Privacy

- Audio is sent directly to OpenAI's Whisper API
- API key is stored in macOS Keychain
- No audio data is stored locally
- All processing is done via OpenAI's secure API

## License

Copyright © 2024 Flow Mac. All rights reserved.
