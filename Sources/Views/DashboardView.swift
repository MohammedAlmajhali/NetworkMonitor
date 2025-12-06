import SwiftUI

/// Main dashboard view showing network usage overview
struct DashboardView: View {
    @ObservedObject var monitorService: NetworkMonitorService
    @State private var selectedApp: AppNetworkUsage?
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .totalBytes
    
    enum SortOrder: String, CaseIterable {
        case totalBytes = "Total"
        case downloaded = "Downloaded"
        case uploaded = "Uploaded"
        case name = "Name"
        case downloadRate = "Speed ↓"
        case uploadRate = "Speed ↑"
    }
    
    var filteredAndSortedApps: [AppNetworkUsage] {
        var apps = monitorService.appUsages
        
        // Filter by search
        if !searchText.isEmpty {
            apps = apps.filter {
                $0.appInfo.name.localizedCaseInsensitiveContains(searchText) ||
                $0.appInfo.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Sort
        switch sortOrder {
        case .totalBytes:
            apps.sort { $0.totalBytes > $1.totalBytes }
        case .downloaded:
            apps.sort { $0.bytesReceived > $1.bytesReceived }
        case .uploaded:
            apps.sort { $0.bytesSent > $1.bytesSent }
        case .name:
            apps.sort { $0.appInfo.name.localizedCompare($1.appInfo.name) == .orderedAscending }
        case .downloadRate:
            apps.sort { $0.downloadRate > $1.downloadRate }
        case .uploadRate:
            apps.sort { $0.uploadRate > $1.uploadRate }
        }
        
        return apps
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with total stats
            HeaderStatsView(
                totalReceived: monitorService.totalBytesReceived,
                totalSent: monitorService.totalBytesSent,
                downloadRate: monitorService.currentDownloadRate,
                uploadRate: monitorService.currentUploadRate,
                isMonitoring: monitorService.isMonitoring,
                appCount: monitorService.appUsages.count
            )
            
            // Search and sort bar
            if !monitorService.appUsages.isEmpty {
                SearchAndSortBar(searchText: $searchText, sortOrder: $sortOrder)
            }
            
            Divider()
            
            // App usage list
            if monitorService.appUsages.isEmpty {
                EmptyStateView(isMonitoring: monitorService.isMonitoring)
            } else if filteredAndSortedApps.isEmpty {
                NoResultsView(searchText: searchText)
            } else {
                AppUsageListView(
                    appUsages: filteredAndSortedApps,
                    selectedApp: $selectedApp
                )
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

/// Search and sort controls bar
struct SearchAndSortBar: View {
    @Binding var searchText: String
    @Binding var sortOrder: DashboardView.SortOrder
    
    var body: some View {
        HStack(spacing: 12) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                TextField("Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 200)
            
            Spacer()
            
            // Sort picker
            HStack(spacing: 4) {
                Text("Sort:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $sortOrder) {
                    ForEach(DashboardView.SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}

/// Header showing total network statistics
struct HeaderStatsView: View {
    let totalReceived: UInt64
    let totalSent: UInt64
    let downloadRate: Double
    let uploadRate: Double
    let isMonitoring: Bool
    let appCount: Int
    
    @State private var animateGradient = false
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Animated gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.2),
                        Color(red: 0.15, green: 0.1, blue: 0.25),
                        Color(red: 0.1, green: 0.15, blue: 0.2)
                    ],
                    startPoint: animateGradient ? .topLeading : .bottomLeading,
                    endPoint: animateGradient ? .bottomTrailing : .topTrailing
                )
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: animateGradient)
                .onAppear { animateGradient = true }
                
                // Subtle mesh overlay
                RadialGradient(
                    colors: [
                        Color.blue.opacity(0.1),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 50,
                    endRadius: 300
                )
                
                RadialGradient(
                    colors: [
                        Color.purple.opacity(0.08),
                        Color.clear
                    ],
                    center: .bottomTrailing,
                    startRadius: 50,
                    endRadius: 250
                )
                
                // Content
                VStack(spacing: 16) {
                    // Stats cards row
                    HStack(spacing: 16) {
                        // Download card
                        ModernStatCard(
                            title: "Downloaded",
                            value: ByteFormatter.shared.format(totalReceived),
                            rate: ByteFormatter.shared.formatRate(downloadRate),
                            icon: "arrow.down.circle.fill",
                            iconColor: .cyan,
                            accentGradient: [.blue, .cyan]
                        )
                        
                        // Upload card
                        ModernStatCard(
                            title: "Uploaded",
                            value: ByteFormatter.shared.format(totalSent),
                            rate: ByteFormatter.shared.formatRate(uploadRate),
                            icon: "arrow.up.circle.fill",
                            iconColor: .green,
                            accentGradient: [.green, .mint]
                        )
                        
                        // Total card
                        ModernStatCard(
                            title: "Total",
                            value: ByteFormatter.shared.format(totalReceived + totalSent),
                            rate: ByteFormatter.shared.formatRate(downloadRate + uploadRate),
                            icon: "arrow.up.arrow.down.circle.fill",
                            iconColor: .purple,
                            accentGradient: [.purple, .pink]
                        )
                        
                        Spacer()
                        
                        // Status badge
                        ModernStatusBadge(isMonitoring: isMonitoring, appCount: appCount)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 20)
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 0))
        }
    }
}

/// Modern glassmorphism stat card
struct ModernStatCard: View {
    let title: String
    let value: String
    let rate: String
    let icon: String
    let iconColor: Color
    let accentGradient: [Color]
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Glowing icon
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [iconColor.opacity(0.4), iconColor.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 30
                        )
                    )
                    .frame(width: 60, height: 60)
                    .blur(radius: 8)
                
                // Icon circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: accentGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)
                    .shadow(color: iconColor.opacity(0.5), radius: isHovered ? 12 : 6, y: 3)
                
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                        .foregroundColor(iconColor)
                    Text(rate)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial.opacity(0.5))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.2), radius: isHovered ? 12 : 6, y: 4)
        )
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Modern status badge
struct ModernStatusBadge: View {
    let isMonitoring: Bool
    let appCount: Int
    
    @State private var pulseAnimation = false
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            // Status indicator
            HStack(spacing: 8) {
                ZStack {
                    // Pulse ring
                    if isMonitoring {
                        Circle()
                            .stroke(Color.green.opacity(0.4), lineWidth: 2)
                            .frame(width: 18, height: 18)
                            .scaleEffect(pulseAnimation ? 1.5 : 1.0)
                            .opacity(pulseAnimation ? 0 : 0.8)
                            .animation(
                                .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                                value: pulseAnimation
                            )
                    }
                    
                    // Core dot
                    Circle()
                        .fill(
                            isMonitoring
                                ? LinearGradient(colors: [.green, .mint], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [.gray, .gray.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 12, height: 12)
                        .shadow(color: isMonitoring ? .green.opacity(0.6) : .clear, radius: 4)
                }
                .onAppear { 
                    if isMonitoring { pulseAnimation = true }
                }
                .onChange(of: isMonitoring) { newValue in
                    pulseAnimation = newValue
                }
                
                Text(isMonitoring ? "Monitoring" : "Stopped")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial.opacity(0.4))
                    .overlay(
                        Capsule()
                            .stroke(
                                isMonitoring 
                                    ? Color.green.opacity(0.3) 
                                    : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
            
            // App count
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                
                Text("\(appCount) apps tracked")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.trailing, 4)
    }
}

/// Glass-morphism style stat card (legacy - kept for compatibility)
struct GlassStatCard: View {
    let title: String
    let value: String
    let rate: String
    let icon: String
    let gradient: Gradient
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon with gradient background
            ZStack {
                Circle()
                    .fill(LinearGradient(gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .shadow(color: gradient.stops.first?.color.opacity(0.3) ?? .clear, radius: isHovered ? 8 : 4, y: 2)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8))
                        .foregroundColor(gradient.stops.first?.color ?? .secondary)
                    Text(rate)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.8 : 0.5))
                .shadow(color: .black.opacity(0.05), radius: isHovered ? 8 : 4, y: 2)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .padding(.horizontal, 4)
    }
}

/// Empty state when no data is available
struct EmptyStateView: View {
    let isMonitoring: Bool
    
    @State private var animationPhase = 0.0
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Animated rings
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: CGFloat(60 + i * 30), height: CGFloat(60 + i * 30))
                        .opacity(isMonitoring ? 0.6 - Double(i) * 0.15 : 0.2)
                        .scaleEffect(isMonitoring ? 1.0 + sin(animationPhase + Double(i) * 0.5) * 0.1 : 1.0)
                }
                
                Image(systemName: isMonitoring ? "network" : "network.slash")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .onAppear {
                if isMonitoring {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        animationPhase = .pi * 2
                    }
                }
            }
            
            VStack(spacing: 8) {
                Text(isMonitoring ? "Waiting for network activity..." : "Monitoring is stopped")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(isMonitoring 
                     ? "Network usage from applications will appear here as they communicate"
                     : "Click the Start button in the toolbar to begin tracking network usage")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

/// No search results view
struct NoResultsView: View {
    let searchText: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("No results for \"\(searchText)\"")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Try a different search term")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

/// List of applications and their network usage
struct AppUsageListView: View {
    let appUsages: [AppNetworkUsage]
    @Binding var selectedApp: AppNetworkUsage?
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(Array(appUsages.enumerated()), id: \.element.id) { index, usage in
                    AppUsageRowView(usage: usage, rank: index + 1, isSelected: selectedApp?.id == usage.id)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedApp = selectedApp?.id == usage.id ? nil : usage
                            }
                        }
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

/// Individual row showing app network usage
struct AppUsageRowView: View {
    let usage: AppNetworkUsage
    let rank: Int
    let isSelected: Bool
    
    @State private var isHovered = false
    
    // Calculate the percentage for the usage bar (relative to max in list)
    private var usagePercentage: Double {
        // This is a simplified version - in real app you'd pass the max value
        min(1.0, Double(usage.totalBytes) / Double(max(usage.totalBytes, 1)))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Rank badge
                RankBadge(rank: rank)
                
                // App icon
                AppIconView(iconPath: usage.appInfo.iconPath, name: usage.appInfo.name)
                
                // App name and bundle ID
                VStack(alignment: .leading, spacing: 3) {
                    Text(usage.appInfo.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    
                    Text(usage.appInfo.bundleIdentifier)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Network stats with rates
                HStack(spacing: 24) {
                    NetworkStatColumn(
                        value: usage.formattedBytesReceived,
                        rate: usage.formattedDownloadRate,
                        icon: "arrow.down",
                        color: .blue
                    )
                    
                    NetworkStatColumn(
                        value: usage.formattedBytesSent,
                        rate: usage.formattedUploadRate,
                        icon: "arrow.up",
                        color: .green
                    )
                    
                    // Total
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(usage.formattedTotalBytes)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Total")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 85, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Expanded details
            if isSelected {
                AppDetailView(usage: usage)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

/// Rank badge for top apps
struct RankBadge: View {
    let rank: Int
    
    var backgroundColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray.opacity(0.8)
        case 3: return .orange.opacity(0.7)
        default: return .secondary.opacity(0.3)
        }
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 24, height: 24)
            
            Text("\(rank)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(rank <= 3 ? .white : .secondary)
        }
    }
}

/// Network stat column with icon
struct NetworkStatColumn: View {
    let value: String
    let rate: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
            }
            
            Text(rate)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(width: 100, alignment: .trailing)
    }
}

/// Expanded detail view for selected app
struct AppDetailView: View {
    let usage: AppNetworkUsage
    
    var body: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.horizontal)
            
            HStack(spacing: 40) {
                DetailItem(label: "First seen", value: formatDate(usage.firstSeen))
                DetailItem(label: "Last activity", value: formatDate(usage.lastUpdated))
                DetailItem(label: "Samples", value: "\(usage.sampleCount)")
                DetailItem(label: "Avg. Download", value: ByteFormatter.shared.formatRate(usage.averageDownloadRate))
                DetailItem(label: "Avg. Upload", value: ByteFormatter.shared.formatRate(usage.averageUploadRate))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Detail item for expanded view
struct DetailItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
        }
    }
}

/// App icon view with fallback
struct AppIconView: View {
    let iconPath: String?
    let name: String
    
    var body: some View {
        Group {
            if let iconPath = iconPath,
               let nsImage = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
            } else {
                // Fallback icon with gradient
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.6), .purple.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: 36, height: 36)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
    }
}

/// Small usage stat display (legacy support)
struct UsageStatView: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(color)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}
