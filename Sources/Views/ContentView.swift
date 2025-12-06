import SwiftUI

/// Main content view with toolbar controls
struct ContentView: View {
    @StateObject private var monitorService = NetworkMonitorService()
    @State private var showingResetAlert = false
    @State private var showingAbout = false
    
    var body: some View {
        DashboardView(monitorService: monitorService)
            .frame(minWidth: 800, minHeight: 500)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    // App title/logo
                    HStack(spacing: 8) {
                        Image(systemName: "network")
                            .font(.title2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("Network Monitor")
                            .font(.headline)
                    }
                }
                
                ToolbarItemGroup(placement: .primaryAction) {
                    // Start/Stop button with animation
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if monitorService.isMonitoring {
                                monitorService.stopMonitoring()
                            } else {
                                monitorService.startMonitoring()
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: monitorService.isMonitoring ? "stop.fill" : "play.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text(monitorService.isMonitoring ? "Stop" : "Start")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(monitorService.isMonitoring ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                        )
                        .foregroundColor(monitorService.isMonitoring ? .red : .green)
                    }
                    .buttonStyle(.plain)
                    .help(monitorService.isMonitoring ? "Stop monitoring (⌘.)" : "Start monitoring (⌘M)")
                    .keyboardShortcut(monitorService.isMonitoring ? "." : "m", modifiers: .command)
                    
                    Divider()
                    
                    // Reset button
                    Button(action: {
                        showingResetAlert = true
                    }) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 13))
                    }
                    .help("Reset all statistics (⇧⌘R)")
                    .disabled(monitorService.appUsages.isEmpty && monitorService.totalBytesReceived == 0)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    
                    // Info button
                    Button(action: {
                        showingAbout = true
                    }) {
                        Label("About", systemImage: "info.circle")
                            .font(.system(size: 13))
                    }
                    .help("About Network Monitor")
                }
            }
            .alert("Reset Statistics", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    withAnimation {
                        monitorService.resetStats()
                    }
                }
            } message: {
                Text("Are you sure you want to reset all network usage statistics? This action cannot be undone.")
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .onAppear {
                // Auto-start monitoring when app launches
                monitorService.startMonitoring()
            }
            .onReceive(NotificationCenter.default.publisher(for: .startMonitoring)) { _ in
                monitorService.startMonitoring()
            }
            .onReceive(NotificationCenter.default.publisher(for: .stopMonitoring)) { _ in
                monitorService.stopMonitoring()
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetStats)) { _ in
                showingResetAlert = true
            }
    }
}

/// About view sheet
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // App icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "network")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(color: .purple.opacity(0.3), radius: 10, y: 5)
            
            VStack(spacing: 8) {
                Text("Network Monitor")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Version 1.0")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text("A real-time network usage monitor for macOS that tracks bandwidth consumption per application.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            
            Divider()
                .frame(width: 200)
            
            VStack(spacing: 6) {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    ShortcutRow(keys: "⌘M", description: "Start monitoring")
                    ShortcutRow(keys: "⌘.", description: "Stop monitoring")
                    ShortcutRow(keys: "⇧⌘R", description: "Reset statistics")
                }
            }
            
            Spacer()
            
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.escape)
            .buttonStyle(.borderedProminent)
        }
        .padding(30)
        .frame(width: 400, height: 450)
    }
}

/// Shortcut row for about view
struct ShortcutRow: View {
    let keys: String
    let description: String
    
    var body: some View {
        HStack {
            Text(keys)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
