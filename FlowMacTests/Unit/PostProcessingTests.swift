import XCTest
@testable import FlowMac

/// Covers the pure post-processing and settings-resolution logic: no network,
/// no audio hardware.
final class PostProcessingTests: XCTestCase {

    private let languageKey = "recognitionLanguage"
    private var savedLanguage: String?
    private var savedDeviceSelection: String?

    override func setUp() {
        super.setUp()
        savedLanguage = UserDefaults.standard.string(forKey: languageKey)
        savedDeviceSelection = UserDefaults.standard.string(forKey: AudioDeviceLookup.selectionKey)
    }

    override func tearDown() {
        restore(savedLanguage, forKey: languageKey)
        restore(savedDeviceSelection, forKey: AudioDeviceLookup.selectionKey)
        super.tearDown()
    }

    private func restore(_ value: String?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - TranscriptionCleaner

    func testStripsWhisperArtifactMarkers() {
        XCTAssertEqual(TranscriptionCleaner.clean("[music] hello world"), "hello world")
        XCTAssertEqual(TranscriptionCleaner.clean("привет (тишина) мир"), "привет мир")
        XCTAssertEqual(TranscriptionCleaner.clean("[BLANK_AUDIO]"), "")
        XCTAssertEqual(TranscriptionCleaner.clean("♪♪ поехали"), "поехали")
    }

    /// The previous implementation deleted every bracketed group, so dictated
    /// parentheses silently vanished from the injected text.
    func testKeepsDictatedParentheses() {
        XCTAssertEqual(
            TranscriptionCleaner.clean("возьми массив (первый элемент) и удвой"),
            "возьми массив (первый элемент) и удвой"
        )
        XCTAssertEqual(TranscriptionCleaner.clean("call foo(bar)"), "call foo(bar)")
    }

    /// Several groups in one line, mixing artifacts with real speech, exercises the
    /// cursor arithmetic that replaced the old in-place mutation.
    func testMixedArtifactsAndParenthesesInOneLine() {
        XCTAssertEqual(
            TranscriptionCleaner.clean("[music] открой файл (второй) потом (тишина) закрой [applause]"),
            "открой файл (второй) потом закрой"
        )
    }

    func testCollapsesWhitespaceAndTrims() {
        XCTAssertEqual(TranscriptionCleaner.clean("  a    b  "), "a b")
    }

    // MARK: - safeMerge

    func testSafeMergeAcceptsSmallGrammarFixes() {
        let original = "мы поехали в магазин и купили молоко хлеб и сыр"
        let corrected = "Мы поехали в магазин и купили молоко, хлеб и сыр."
        XCTAssertEqual(
            SemanticCorrectionService.safeMerge(original: original, corrected: corrected, maxChangeRatio: 0.25),
            corrected
        )
    }

    func testSafeMergeRejectsHallucination() {
        let original = "привет как дела"
        let corrected = "Here is a completely different sentence about something else entirely."
        XCTAssertEqual(
            SemanticCorrectionService.safeMerge(original: original, corrected: corrected, maxChangeRatio: 0.25),
            original
        )
    }

    func testNormalizedEditDistanceBounds() {
        XCTAssertEqual(SemanticCorrectionService.normalizedEditDistance("abc", "abc"), 0.0)
        XCTAssertEqual(SemanticCorrectionService.normalizedEditDistance("abc", "xyz"), 1.0)
    }

    // MARK: - AppCategory

    func testDetectsCategoryFromBundleIdentifier() {
        XCTAssertEqual(AppCategory.detect(bundleIdentifier: "com.apple.Terminal"), .terminal)
        XCTAssertEqual(AppCategory.detect(bundleIdentifier: "com.microsoft.VSCode"), .coding)
        XCTAssertEqual(AppCategory.detect(bundleIdentifier: "com.tinyspeck.slackmacgap"), .chat)
        XCTAssertEqual(AppCategory.detect(bundleIdentifier: nil), .general)
    }

    func testEveryCategoryPromptCarriesTheSharedRules() {
        for category in AppCategory.allCases {
            XCTAssertTrue(
                category.systemPrompt.contains("same language as the input"),
                "\(category.rawValue) prompt lost the language-preservation rule"
            )
        }
    }

    // MARK: - Language selection

    func testLanguageDefaultsToAutoDetect() {
        UserDefaults.standard.removeObject(forKey: languageKey)
        XCTAssertEqual(RecognitionService.currentLanguage, "auto")
    }

    func testStoredLanguageWins() {
        UserDefaults.standard.set("ru", forKey: languageKey)
        XCTAssertEqual(RecognitionService.currentLanguage, "ru")
    }

    func testSupportedLanguagesStartWithAutoDetect() {
        XCTAssertEqual(RecognitionService.supportedLanguages.first?.0, "auto")
    }

    // MARK: - Audio device selection

    /// A stored raw AudioDeviceID refers to whatever device holds that id now, which is
    /// how the engine ended up retrying a dead device on every reconfigure.
    func testLegacyNumericDeviceSelectionMigratesToDefault() {
        UserDefaults.standard.set("78", forKey: AudioDeviceLookup.selectionKey)
        XCTAssertEqual(AudioDeviceLookup.selectedDeviceUID(), AudioDeviceLookup.systemDefault)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: AudioDeviceLookup.selectionKey),
            AudioDeviceLookup.systemDefault,
            "migration must be persisted, not recomputed on every read"
        )
    }

    func testUIDSelectionIsPreserved() {
        let uid = "BuiltInMicrophoneDevice"
        UserDefaults.standard.set(uid, forKey: AudioDeviceLookup.selectionKey)
        XCTAssertEqual(AudioDeviceLookup.selectedDeviceUID(), uid)
    }

    func testMissingDeviceSelectionFallsBackToDefault() {
        UserDefaults.standard.removeObject(forKey: AudioDeviceLookup.selectionKey)
        XCTAssertEqual(AudioDeviceLookup.selectedDeviceUID(), AudioDeviceLookup.systemDefault)
    }

    func testUnknownUIDDoesNotResolve() {
        XCTAssertNil(AudioDeviceLookup.deviceID(forUID: "definitely-not-a-real-device-uid"))
    }
}
