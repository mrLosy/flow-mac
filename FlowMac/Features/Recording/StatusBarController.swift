import SwiftUI
import AppKit
import Combine

/// Controller for the status bar menu
@MainActor
class StatusBarController: NSObject, ObservableObject {
    private var statusBar: NSStatusBar
    private var statusItem: NSStatusItem
    private var popover: NSPopover?
    private var audioEngine: AudioEngine
    private var recognitionService: RecognitionService
    private var textInjector: TextInjector
    
    @Published var isRecording = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init(
        audioEngine: AudioEngine,
        recognitionService: RecognitionService,
        textInjector: TextInjector
    ) {
        self.audioEngine = audioEngine
        self.recognitionService = recognitionService
        self.textInjector = textInjector

        statusBar = NSStatusBar.system
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        setupStatusBar()
        setupPopover()
        setupObservers()
    }
    
    private func setupStatusBar() {
        statusItem.autosaveName = "FlowMacStatusItem"
        statusItem.behavior = []
        statusItem.isVisible = true

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Flow Mac")
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShowRequest),
            name: StatusBarController.showRequestNotification,
            object: nil
        )

        updateMenuIcon()
    }

    @objc private func handleShowRequest() {
        statusItem.isVisible = true
        DebugLog.log("UI. show-request received — status item forced visible")
        guard let button = statusItem.button else { return }
        toggleMainPopover(button)
    }

    static let showRequestNotification = Notification.Name("com.flowmac.app.showStatusItem")
    
    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        
        let contentView = StatusBarMenuView(
            audioEngine: audioEngine,
            recognitionService: recognitionService,
            textInjector: textInjector,
            historyService: TranscriptionHistoryService.shared,
            openSettings: { [weak self] in
                self?.openSettings()
            },
            quitApp: { [weak self] in
                self?.quitApp()
            }
        )
        
        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover
    }
    
    private func setupObservers() {
        // Observe recording state changes
        audioEngine.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                self?.isRecording = isRecording
                self?.updateMenuIcon()
            }
            .store(in: &cancellables)

        // Observe quota changes to update menu bar icon tint
        QuotaService.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenuIcon() }
            .store(in: &cancellables)
    }

    private func updateMenuIcon() {
        guard let button = statusItem.button else { return }

        if isRecording {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Recording")
            button.contentTintColor = .systemRed
            return
        }

        let state = QuotaService.shared.state
        if state.plan.usesBackend && state.isExhausted {
            // Exhausted — use a symbol that visually warns
            let warning = NSImage(systemSymbolName: "waveform.badge.exclamationmark", accessibilityDescription: "Quota exhausted")
                ?? NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Flow Mac")
            button.image = warning
            button.contentTintColor = .systemOrange
        } else if state.plan.usesBackend && state.usageRatio >= 0.9 {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Flow Mac")
            button.contentTintColor = .systemOrange
        } else {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Flow Mac")
            button.contentTintColor = nil
        }
    }
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        
        let event = NSApp.currentEvent
        
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleMainPopover(button)
        }
    }
    
    private func toggleMainPopover(_ button: NSStatusBarButton) {
        if let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        let toggleItem = NSMenuItem(
            title: isRecording ? "Stop Recording" : "Start Recording",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        let transcribeItem = NSMenuItem(
            title: "Transcribe Audio File...",
            action: #selector(transcribeFile),
            keyEquivalent: ""
        )
        transcribeItem.target = self
        menu.addItem(transcribeItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(
            title: "Quit Flow Mac",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    
    @objc private func toggleRecording() {
        DebugLog.log("UI. toggleRecording button pressed")
        NotificationCenter.default.post(name: .toggleRecording, object: nil)
    }

    @objc private func transcribeFile() {
        FileTranscriptionService.shared.transcribeFromFilePicker(using: recognitionService)
    }
    
    private var settingsWindow: NSWindow?

    @objc private func openSettings() {
        popover?.performClose(nil)

        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Flow Mac Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.settingsWindow = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            NSApp.setActivationPolicy(.accessory)
            self?.settingsWindow = nil
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let toggleRecording = Notification.Name("toggleRecording")
    static let hotkeyDidChange = Notification.Name("hotkeyDidChange")
    static let retryTranscription = Notification.Name("retryTranscription")
}
