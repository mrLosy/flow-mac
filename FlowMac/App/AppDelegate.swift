import Foundation
import AppKit

/// AppDelegate for handling app lifecycle events
class AppDelegate: NSObject, NSApplicationDelegate {
    // AppDelegate is primarily a placeholder now
    // Main setup happens in FlowMacApp.swift
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running in menu bar
    }
}
