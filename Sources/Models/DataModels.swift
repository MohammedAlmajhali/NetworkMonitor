import Foundation

/// Utility for formatting byte values into human-readable strings
struct ByteFormatter {
    static let shared = ByteFormatter()
    
    private let formatter: ByteCountFormatter
    private let rateFormatter: ByteCountFormatter
    
    init() {
        formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .binary
        
        rateFormatter = ByteCountFormatter()
        rateFormatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        rateFormatter.countStyle = .binary
        rateFormatter.includesUnit = true
    }
    
    func format(_ bytes: UInt64) -> String {
        formatter.string(fromByteCount: Int64(bytes))
    }
    
    func format(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
    
    /// Format a rate value (bytes per second) as human-readable string
    func formatRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1 {
            return "0 B/s"
        }
        let formatted = rateFormatter.string(fromByteCount: Int64(bytesPerSecond))
        return "\(formatted)/s"
    }
}

/// Time range options for filtering statistics
enum TimeRange: String, CaseIterable, Identifiable {
    case session = "This Session"
    case lastHour = "Last Hour"
    case today = "Today"
    case week = "This Week"
    
    var id: String { rawValue }
}

/// Network usage summary statistics
struct UsageSummary {
    let totalReceived: UInt64
    let totalSent: UInt64
    let topApps: [AppNetworkUsage]
    let activeAppCount: Int
    let currentDownloadRate: Double
    let currentUploadRate: Double
    
    var totalBytes: UInt64 {
        totalReceived + totalSent
    }
}

extension AppNetworkUsage {
    /// Format bytes received as human-readable string
    var formattedBytesReceived: String {
        ByteFormatter.shared.format(bytesReceived)
    }
    
    /// Format bytes sent as human-readable string
    var formattedBytesSent: String {
        ByteFormatter.shared.format(bytesSent)
    }
    
    /// Format total bytes as human-readable string
    var formattedTotalBytes: String {
        ByteFormatter.shared.format(totalBytes)
    }
    
    /// Format current download rate
    var formattedDownloadRate: String {
        ByteFormatter.shared.formatRate(downloadRate)
    }
    
    /// Format current upload rate
    var formattedUploadRate: String {
        ByteFormatter.shared.formatRate(uploadRate)
    }
}
