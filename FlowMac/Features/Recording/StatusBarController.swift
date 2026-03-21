import SwiftUI
import AppKit

/// Controller for the status bar menu
class StatusBarController: ObservableObject {
    private var statusBar: NSStatusBar
    private var statusItem: NSStatusItem
    private var popover: NSPopover?
    private var audioEngine: AudioEngine
    private var recognitionService: RecognitionService
    private var textInjector: TextInjector
    
    @Published var isRecording = false
    
    init(
        audioEngine: AudioEngine,
        recognitionService: RecognitionService,
        textInjector: TextInjector
    ) {
        self.audioEngine = audioEngine
        self.recognitionService = recognitionService
        self.textInjector = textInjector
        
        statusBar = NSStatusBar()
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        
        setupStatusBar()
        setupPopover()
        setupObservers()
    }
    
    private func setupStatusBar() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Flow Mac")
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        updateMenuIcon()
    }
    
    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 350)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: StatusBarMenuView(
                audioEngine: audioEngine,
                recognitionService: recognitionService,
                textInjector: textInjector,
                openSettings: { [weak self] in
                    self?.openSettings()
                },
                quitApp: { [weak self] in
                    self?.quitApp()
                }
            )
        )
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
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func updateMenuIcon() {
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.statusItem.button else { return }
            
            if self?.isRecording == true {
                button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Recording")
                button.contentTintColor = .systemRed
            } else {
                button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Flow Mac")
                button.contentTintColor = nil
            }
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
        // This will be handled by HotkeyManager
        NotificationCenter.default.post(name: .toggleRecording, object: nil)
    }
    
    @objc private func openSettings() {
        popover?.performClose(nil)
        
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Open settings window
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let toggleRecording = Notification.Name("toggleRecording")
}
