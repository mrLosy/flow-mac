# Task 5: Подготовка к App Store submission

## Цель

Подготовить Flow Mac к публикации в Mac App Store: проверить sandbox совместимость, entitlements, Hardened Runtime, метаданные, скриншоты, и пройти review.

## Контекст

Flow Mac — macOS 13.0+ menu bar приложение для голосовой диктовки. Использует:
- **Microphone** (AVFoundation) — запись голоса
- **Accessibility API** (AXUIElement) — вставка текста в курсор
- **CGEventTap** — глобальные хоткеи
- **Network** — облачная транскрипция
- **StoreKit 2** — подписки и покупки

Это сочетание требует особого внимания при review, т.к. Accessibility и CGEventTap — чувствительные разрешения.

## Текущие entitlements

Файл: `FlowMac/Resources/FlowMac.entitlements`

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.automation.apple-events</key>
<true/>
<key>com.apple.security.temporary-exception.apple-events</key>
<array>
    <string>com.apple.systemevents</string>
</array>
```

## Что нужно проверить и доработать

### 1. Sandbox и CGEventTap

**Проблема:** App Sandbox ограничивает `CGEventTap`. В sandboxed apps `CGEventTapCreate` может не работать без явного permission grant.

**Текущее решение в коде:** HotkeyManager использует `CGEventTapCreate` как primary, с fallback на `NSEvent.addGlobalMonitorForEvents`. Это корректный подход.

**Что проверить:**
- [ ] Хоткей работает в sandbox mode (собрать с Release конфигурацией)
- [ ] Если CGEventTap блокируется — NSEvent fallback срабатывает
- [ ] Input Monitoring permission запрашивается корректно

### 2. Hardened Runtime

Для App Store нужен Hardened Runtime. В Build Settings:

```
ENABLE_HARDENED_RUNTIME = YES
```

Проверить что в entitlements есть все нужные runtime exceptions:
- `com.apple.security.cs.allow-unsigned-executable-memory` — **НЕ нужен** (нет JIT)
- `com.apple.security.device.audio-input` — **есть**

### 3. Info.plist — Usage Descriptions

Файл: `FlowMac/Resources/Info.plist`

Что должно быть:

| Ключ | Значение | Статус |
|---|---|---|
| NSMicrophoneUsageDescription | "Flow Mac needs microphone access to record your voice for transcription." | Проверить текст |
| NSAccessibilityUsageDescription | "Flow Mac needs accessibility access to insert transcribed text at your cursor position." | Проверить наличие |

**Отсутствует (добавить):**

| Ключ | Значение |
|---|---|
| NSInputMonitoringUsageDescription | "Flow Mac needs input monitoring to detect global keyboard shortcuts." |

### 4. App Icons

Нужен .icns файл или Asset Catalog с macOS app icon:
- 16x16, 32x32, 128x128, 256x256, 512x512, 1024x1024
- Проверить: `FlowMac/Resources/Assets.xcassets/AppIcon.appiconset`

### 5. App Store Метаданные

| Поле | Значение |
|---|---|
| App Name | Flow Mac |
| Subtitle | Voice Dictation with AI |
| Category | Productivity |
| Secondary Category | Utilities |
| Privacy Policy URL | https://flowmac.app/privacy (нужно создать) |
| Support URL | https://github.com/flowmac/issues (или свой) |
| Marketing URL | https://flowmac.app |
| Age Rating | 4+ |
| Price | Free (with in-app purchases) |

### 6. Скриншоты

Mac App Store требует скриншоты для конкретных разрешений:
- 1280x800 или 1440x900 (минимум)
- 2560x1600 или 2880x1800 (Retina)

**Рекомендуемые скриншоты (5 штук):**
1. Menu bar popover — основной интерфейс со статусом "Ready"
2. Recording state — waveform анимация при записи
3. Settings — Account tab с квотой
4. PaywallView — экран подписок
5. Text injection — результат вставки в текстовый редактор

### 7. App Review Notes

```
Flow Mac is a macOS menu bar voice dictation utility. Users press a 
keyboard shortcut to record speech, which is transcribed using AI and 
automatically inserted at the cursor position.

PERMISSIONS REQUIRED:
- Microphone: Records user's voice for transcription
- Accessibility: Detects focused text field and inserts transcribed text
- Input Monitoring: Listens for global keyboard shortcuts (Cmd+Shift+Space)
- Network: Sends audio to our transcription server

SUBSCRIPTION MODEL:
- Free tier: 15 minutes/month of dictation (no payment required)
- Basic: $4.99/month for 120 minutes
- Pro: $9.99/month for 500 minutes
- Lifetime: $29.99 one-time (user provides their own API keys)

The app does NOT store audio after transcription is complete.
Audio is sent to our server, processed via Groq Whisper API, and deleted.

Demo credentials for testing:
- Launch the app, it starts with Free tier (15 min/month)
- Press Cmd+Shift+Space to start recording
- Speak and release to get transcription
```

### 8. Privacy Nutrition Labels

App Store privacy labels (App Privacy):

| Data Type | Collected | Linked to User | Tracking |
|---|---|---|---|
| Audio Data | Yes | No | No |
| Purchases | Yes | Yes | No |
| User ID (Apple Sign In) | Yes | Yes | No |
| Usage Data (quota tracking) | Yes | Yes | No |

**Data NOT collected:**
- Location, Contacts, Photos, Health, Financial, Sensitive Info, Browsing History, Search History, Identifiers, Diagnostics

### 9. Xcode Archive & Upload

```bash
# 1. Clean build
xcodebuild clean -project FlowMac.xcodeproj -scheme FlowMac

# 2. Archive
xcodebuild archive -project FlowMac.xcodeproj -scheme FlowMac \
  -archivePath ./build/FlowMac.xcarchive

# 3. Export for App Store
xcodebuild -exportArchive \
  -archivePath ./build/FlowMac.xcarchive \
  -exportPath ./build/export \
  -exportOptionsPlist ExportOptions.plist

# 4. Upload via Transporter app or xcrun altool
xcrun altool --upload-app \
  -f ./build/export/FlowMac.pkg \
  -t macos \
  -u "apple_id@email.com" \
  -p "@keychain:altool"
```

Или через Xcode: Product → Archive → Distribute App → App Store Connect.

## Известные риски при review

| Риск | Вероятность | Митигация |
|---|---|---|
| Accessibility permission rejection | Средняя | Подробные App Review Notes, демо видео |
| CGEventTap в sandbox | Средняя | Fallback на NSEvent.addGlobalMonitor |
| "Thin client" rejection (просто обёртка над API) | Низкая | У нас богатый UI, история, метрики, multiple modes |
| Privacy concerns (аудио на сервер) | Низкая | Privacy Policy, "audio deleted after processing" |

## Чеклист

- [ ] Hardened Runtime включён
- [ ] Все entitlements корректны
- [ ] Info.plist: все Usage Descriptions заполнены (Mic, Accessibility, Input Monitoring)
- [ ] App icon в Asset Catalog (все размеры)
- [ ] Скриншоты подготовлены (5 штук, Retina)
- [ ] Privacy Policy URL создан
- [ ] App Store метаданные заполнены
- [ ] Privacy Nutrition Labels заполнены
- [ ] StoreKit продукты в статусе "Ready to Submit"
- [ ] App Review Notes написаны
- [ ] Archive билд собирается без ошибок
- [ ] Тест в sandboxed environment проходит
- [ ] CGEventTap fallback работает
