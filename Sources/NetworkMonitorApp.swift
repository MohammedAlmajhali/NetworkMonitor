import SwiftUI

/// Main application entry point
@main
struct NetworkMonitorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 850, minHeight: 550)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 950, height: 650)
        .commands {
            // Add menu commands
            CommandGroup(replacing: .newItem) { }
            
            CommandMenu("Monitor") {
                Button("Start Monitoring") {
                    NotificationCenter.default.post(name: .startMonitoring, object: nil)
                }
                .keyboardShortcut("m", modifiers: .command)
                
                Button("Stop Monitoring") {
                    NotificationCenter.default.post(name: .stopMonitoring, object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)
                
                Divider()
                
                Button("Reset Statistics") {
                    NotificationCenter.default.post(name: .resetStats, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            
            // Help menu
            CommandGroup(replacing: .help) {
                Button("Network Monitor Help") {
                    if let url = URL(string: "https://support.apple.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

// Notification names for menu commands
extension Notification.Name {
    static let startMonitoring = Notification.Name("startMonitoring")
    static let stopMonitoring = Notification.Name("stopMonitoring")
    static let resetStats = Notification.Name("resetStats")
}
