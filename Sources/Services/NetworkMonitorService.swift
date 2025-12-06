import Foundation
import Darwin

// MARK: - System API Imports

@_silgen_name("proc_listallpids")
func proc_listallpids(_ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidpath")
func proc_pidpath(_ pid: pid_t, _ buffer: UnsafeMutableRawPointer?, _ buffersize: UInt32) -> Int32

@_silgen_name("proc_name")
func proc_name(_ pid: pid_t, _ buffer: UnsafeMutableRawPointer?, _ buffersize: UInt32) -> Int32

// Constants
let MAXPATHLEN_SIZE: Int = 4096

/// Network statistics tracking using nettop for accurate per-process data
@MainActor
class NetworkMonitorService: ObservableObject {
    @Published var appUsages: [AppNetworkUsage] = []
    @Published var totalBytesReceived: UInt64 = 0
    @Published var totalBytesSent: UInt64 = 0
    @Published var isMonitoring: Bool = false
    @Published var currentDownloadRate: Double = 0
    @Published var currentUploadRate: Double = 0
    
    private var timer: Timer?
    private var accumulatedUsage: [String: AppNetworkUsage] = [:]
    private var appInfoCache: [String: (info: AppInfo, timestamp: Date)] = [:]
    private var previousProcessBytes: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var previousInterfaceBytes: (rx: UInt64, tx: UInt64) = (0, 0)
    private let updateInterval: TimeInterval = 3.0
    private let appInfoCacheTimeout: TimeInterval = 120.0
    private var lastUpdateTime: Date = Date()
    private var nettopProcess: Process?
    
    /// Start monitoring network usage
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        lastUpdateTime = Date()
        
        // Take initial snapshot
        Task {
            await captureNettopSnapshot()
        }
        
        // Schedule periodic updates
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateStats()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    /// Stop monitoring network usage
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        nettopProcess?.terminate()
        nettopProcess = nil
        isMonitoring = false
        currentDownloadRate = 0
        currentUploadRate = 0
    }
    
    /// Reset all collected statistics
    func resetStats() {
        accumulatedUsage.removeAll()
        appInfoCache.removeAll()
        previousProcessBytes.removeAll()
        previousInterfaceBytes = getPhysicalInterfaceBytes()
        appUsages.removeAll()
        totalBytesReceived = 0
        totalBytesSent = 0
        currentDownloadRate = 0
        currentUploadRate = 0
        lastUpdateTime = Date()
    }
    
    /// Capture initial nettop snapshot to establish baseline
    private func captureNettopSnapshot() async {
        let snapshot = await runNettop()
        for (processName, stats) in snapshot {
            previousProcessBytes[processName] = (rx: stats.bytesIn, tx: stats.bytesOut)
        }
        // Capture initial interface bytes
        previousInterfaceBytes = getPhysicalInterfaceBytes()
    }
    
    /// Get bytes from physical network interfaces (what ISP actually bills)
    private func getPhysicalInterfaceBytes() -> (rx: UInt64, tx: UInt64) {
        // Use netstat -ib to get interface statistics
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        task.arguments = ["-ib"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        var totalRx: UInt64 = 0
        var totalTx: UInt64 = 0
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: "\n")
                
                for line in lines {
                    // Only count physical interfaces (en0, en1, etc.) with Link# entries
                    // Skip loopback (lo0), VPN tunnels (utun*), and other virtual interfaces
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    guard parts.count >= 10 else { continue }
                    
                    let interfaceName = String(parts[0])
                    let network = String(parts[2])
                    
                    // Only count physical ethernet/wifi interfaces with Link layer stats
                    guard interfaceName.hasPrefix("en") && network.hasPrefix("<Link#") else { continue }
                    
                    // Columns: Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes
                    if let ibytes = UInt64(parts[6]), let obytes = UInt64(parts[9]) {
                        totalRx += ibytes
                        totalTx += obytes
                    }
                }
            }
        } catch {
            // Silently fail
        }
        
        return (rx: totalRx, tx: totalTx)
    }
    
    /// Update network statistics using nettop
    private func updateStats() async {
        let now = Date()
        let timeDelta = now.timeIntervalSince(lastUpdateTime)
        guard timeDelta > 0.5 else { return }
        
        // Get physical interface bytes (what ISP actually measures)
        let currentInterfaceBytes = getPhysicalInterfaceBytes()
        let interfaceDeltaRx = currentInterfaceBytes.rx > previousInterfaceBytes.rx 
            ? currentInterfaceBytes.rx - previousInterfaceBytes.rx : 0
        let interfaceDeltaTx = currentInterfaceBytes.tx > previousInterfaceBytes.tx 
            ? currentInterfaceBytes.tx - previousInterfaceBytes.tx : 0
        previousInterfaceBytes = currentInterfaceBytes
        
        // Get current nettop data for per-process breakdown
        let currentSnapshot = await runNettop()
        
        // Calculate raw nettop deltas (may include retransmissions/overhead)
        var rawProcessDeltas: [(appInfo: AppInfo, deltaRx: UInt64, deltaTx: UInt64)] = []
        var totalRawRx: UInt64 = 0
        var totalRawTx: UInt64 = 0
        
        for (processName, stats) in currentSnapshot {
            let deltaRx: UInt64
            let deltaTx: UInt64
            
            if let previous = previousProcessBytes[processName] {
                deltaRx = stats.bytesIn >= previous.rx ? stats.bytesIn - previous.rx : stats.bytesIn
                deltaTx = stats.bytesOut >= previous.tx ? stats.bytesOut - previous.tx : stats.bytesOut
            } else {
                deltaRx = 0
                deltaTx = 0
            }
            
            previousProcessBytes[processName] = (rx: stats.bytesIn, tx: stats.bytesOut)
            
            guard deltaRx > 0 || deltaTx > 0 else { continue }
            
            // Sanity check
            let maxDelta: UInt64 = 500_000_000
            guard deltaRx < maxDelta && deltaTx < maxDelta else { continue }
            
            let appInfo = getAppInfoForProcess(name: processName, pid: stats.pid)
            rawProcessDeltas.append((appInfo: appInfo, deltaRx: deltaRx, deltaTx: deltaTx))
            totalRawRx += deltaRx
            totalRawTx += deltaTx
        }
        
        // Scale per-process usage to match actual interface bytes
        // This removes the overhead/retransmission inflation
        let rxScale = totalRawRx > 0 ? Double(interfaceDeltaRx) / Double(totalRawRx) : 1.0
        let txScale = totalRawTx > 0 ? Double(interfaceDeltaTx) / Double(totalRawTx) : 1.0
        
        // Apply scaled values (cap scale at 1.0 to not inflate if interface shows more)
        let effectiveRxScale = min(rxScale, 1.0)
        let effectiveTxScale = min(txScale, 1.0)
        
        for item in rawProcessDeltas {
            let scaledRx = UInt64(Double(item.deltaRx) * effectiveRxScale)
            let scaledTx = UInt64(Double(item.deltaTx) * effectiveTxScale)
            updateAccumulatedUsage(appInfo: item.appInfo, deltaRx: scaledRx, deltaTx: scaledTx)
        }
        
        // Use interface bytes for totals (most accurate for ISP billing)
        totalBytesReceived += interfaceDeltaRx
        totalBytesSent += interfaceDeltaTx
        
        // Calculate rates from interface bytes
        currentDownloadRate = Double(interfaceDeltaRx) / timeDelta
        currentUploadRate = Double(interfaceDeltaTx) / timeDelta
        
        lastUpdateTime = now
        
        // Update published list
        appUsages = accumulatedUsage.values
            .filter { $0.totalBytes > 0 }
            .sorted { $0.totalBytes > $1.totalBytes }
    }
    
    /// Run nettop command and parse output
    private func runNettop() async -> [String: NettopProcessStats] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var results: [String: NettopProcessStats] = [:]
                
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
                // -P: show per-process, -L 1: one sample, -x: extended numeric display
                task.arguments = ["-P", "-L", "1", "-x"]
                
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = FileHandle.nullDevice
                
                do {
                    try task.run()
                    task.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        results = NettopParser.parseNettopOutput(output)
                    }
                } catch {
                    // nettop failed, try alternative approach
                    results = NettopParser.getNetworkStatsFromNetstat()
                }
                
                continuation.resume(returning: results)
            }
        }
    }
    
    /// Get app info for a process name
    private func getAppInfoForProcess(name: String, pid: pid_t) -> AppInfo {
        let cacheKey = name
        let now = Date()
        
        // Check cache
        if let cached = appInfoCache[cacheKey],
           now.timeIntervalSince(cached.timestamp) < appInfoCacheTimeout {
            return cached.info
        }
        
        // Try to find the app
        var appName = name
        var bundleId = name
        var iconPath: String? = nil
        
        // If we have a PID, try to get more info
        if pid > 0 {
            let detailedInfo = getAppInfo(for: pid)
            appName = detailedInfo.name
            bundleId = detailedInfo.bundleIdentifier
            iconPath = detailedInfo.iconPath
        } else {
            // Try to find by app name in /Applications
            if let appPath = findAppByName(name) {
                if let bundle = Bundle(path: appPath) {
                    if let bundleName = bundle.infoDictionary?["CFBundleName"] as? String {
                        appName = bundleName
                    }
                    bundleId = bundle.bundleIdentifier ?? name
                    if let iconName = bundle.infoDictionary?["CFBundleIconFile"] as? String {
                        iconPath = bundle.path(forResource: iconName.replacingOccurrences(of: ".icns", with: ""), ofType: "icns")
                    }
                }
            }
        }
        
        let info = AppInfo(pid: pid, name: appName, bundleIdentifier: bundleId, iconPath: iconPath)
        appInfoCache[cacheKey] = (info: info, timestamp: now)
        return info
    }
    
    /// Find app bundle by process name
    private func findAppByName(_ name: String) -> String? {
        let searchPaths = [
            "/Applications",
            "/System/Applications", 
            "/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]
        
        let searchNames = [
            name + ".app",
            name.replacingOccurrences(of: " Helper", with: "") + ".app",
            name.replacingOccurrences(of: "Helper", with: "").trimmingCharacters(in: .whitespaces) + ".app"
        ]
        
        for searchPath in searchPaths {
            for searchName in searchNames {
                let fullPath = (searchPath as NSString).appendingPathComponent(searchName)
                if FileManager.default.fileExists(atPath: fullPath) {
                    return fullPath
                }
            }
            
            // Also search subdirectories one level deep
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: searchPath) {
                for item in contents where item.hasSuffix(".app") {
                    let appPath = (searchPath as NSString).appendingPathComponent(item)
                    let appNameFromPath = (item as NSString).deletingPathExtension
                    
                    if name.lowercased().contains(appNameFromPath.lowercased()) ||
                       appNameFromPath.lowercased().contains(name.lowercased()) {
                        return appPath
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Get application information for a process ID
    private func getAppInfo(for pid: pid_t) -> AppInfo {
        var pathBuffer = [CChar](repeating: 0, count: MAXPATHLEN_SIZE)
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        
        var name = "Unknown"
        var bundleIdentifier: String? = nil
        var iconPath: String? = nil
        
        if pathLength > 0 {
            let path = String(cString: pathBuffer)
            
            if let appPath = findAppBundle(from: path) {
                if let bundle = Bundle(path: appPath) {
                    let infoDict = bundle.infoDictionary
                    if let bundleName = infoDict?["CFBundleName"] as? String {
                        name = bundleName
                    } else if let displayName = infoDict?["CFBundleDisplayName"] as? String {
                        name = displayName
                    } else {
                        name = URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
                    }
                    bundleIdentifier = bundle.bundleIdentifier
                    
                    if let infoDict = infoDict,
                       let iconName = infoDict["CFBundleIconFile"] as? String {
                        let iconType: String? = iconName.hasSuffix(".icns") ? nil : "icns"
                        iconPath = bundle.path(forResource: iconName.replacingOccurrences(of: ".icns", with: ""), ofType: iconType ?? "icns")
                    }
                }
            } else {
                name = URL(fileURLWithPath: path).lastPathComponent
            }
        } else {
            var nameBuffer = [CChar](repeating: 0, count: 256)
            _ = proc_name(pid, &nameBuffer, 256)
            if nameBuffer[0] != 0 {
                name = String(cString: nameBuffer)
            }
        }
        
        return AppInfo(
            pid: pid,
            name: name,
            bundleIdentifier: bundleIdentifier ?? name,
            iconPath: iconPath
        )
    }
    
    /// Find the .app bundle path from an executable path
    private func findAppBundle(from path: String) -> String? {
        var url = URL(fileURLWithPath: path)
        
        while url.path != "/" {
            if url.pathExtension == "app" {
                return url.path
            }
            url = url.deletingLastPathComponent()
        }
        
        return nil
    }
    
    /// Update accumulated usage for an application
    private func updateAccumulatedUsage(appInfo: AppInfo, deltaRx: UInt64, deltaTx: UInt64) {
        let key = appInfo.bundleIdentifier
        let now = Date()
        
        if var existing = accumulatedUsage[key] {
            existing.bytesReceived += deltaRx
            existing.bytesSent += deltaTx
            existing.sampleCount += 1
            existing.lastUpdated = now
            
            let timeDelta = now.timeIntervalSince(existing.lastRateUpdate)
            if timeDelta > 0 {
                let instantRxRate = Double(deltaRx) / timeDelta
                let instantTxRate = Double(deltaTx) / timeDelta
                let alpha = 0.3
                existing.downloadRate = alpha * instantRxRate + (1 - alpha) * existing.downloadRate
                existing.uploadRate = alpha * instantTxRate + (1 - alpha) * existing.uploadRate
                existing.lastRateUpdate = now
            }
            
            accumulatedUsage[key] = existing
        } else {
            accumulatedUsage[key] = AppNetworkUsage(
                appInfo: appInfo,
                bytesReceived: deltaRx,
                bytesSent: deltaTx,
                firstSeen: now,
                lastUpdated: now,
                sampleCount: 1,
                downloadRate: 0,
                uploadRate: 0,
                lastRateUpdate: now
            )
        }
    }
}

// MARK: - Data Structures

/// Stats from nettop for a process
struct NettopProcessStats {
    let processName: String
    var pid: pid_t
    var bytesIn: UInt64
    var bytesOut: UInt64
}

/// Information about an application
struct AppInfo: Identifiable, Hashable {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String
    let iconPath: String?
    
    var id: String { bundleIdentifier }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }
    
    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

/// Network usage data for an application
struct AppNetworkUsage: Identifiable {
    let appInfo: AppInfo
    var bytesReceived: UInt64
    var bytesSent: UInt64
    var firstSeen: Date
    var lastUpdated: Date
    var sampleCount: Int
    var downloadRate: Double
    var uploadRate: Double
    var lastRateUpdate: Date
    
    var id: String { appInfo.bundleIdentifier }
    
    var totalBytes: UInt64 {
        bytesReceived + bytesSent
    }
    
    var trackingDuration: TimeInterval {
        lastUpdated.timeIntervalSince(firstSeen)
    }
    
    var averageDownloadRate: Double {
        let duration = trackingDuration
        return duration > 0 ? Double(bytesReceived) / duration : 0
    }
    
    var averageUploadRate: Double {
        let duration = trackingDuration
        return duration > 0 ? Double(bytesSent) / duration : 0
    }
}

// MARK: - Nettop Parser (Thread-safe, non-actor)

/// Parser for nettop and lsof output - runs on background threads
enum NettopParser {
    
    /// Processes that are local-only or should not count as internet traffic
    /// These are either localhost services, local network discovery, or VPN tunnels
    static let localOnlyProcesses: Set<String> = [
        // Local network services
        "mDNSResponder",     // Bonjour/local network discovery
        "netbiosd",          // NetBIOS name resolution
        "rapportd",          // Local device communication
        "sharingd",          // AirDrop/local sharing
        "ControlCenter",     // macOS control center
        "wifip2pd",          // WiFi peer-to-peer
        "wifianalyticsd",    // WiFi analytics
        "wifivelocityd",     // WiFi speed testing
        "airportd",          // WiFi management
        
        // Localhost database/services
        "postgres",          // Local database
        "pgagent",           // PostgreSQL job agent (local)
        "redis-server",      // Local cache
        "MySQL",             // Local database
        "mongod",            // Local database
        
        // VPN tunnel processes (traffic goes through VPN, counted separately)
        "zerotier-one",      // ZeroTier VPN
        "openvpn",           // OpenVPN
        "wireguard-go",      // WireGuard VPN
        "PanGPS",            // GlobalProtect GPS
        "GlobalProtect",     // GlobalProtect VPN client
        "ProtonVPN",         // ProtonVPN client app
        "NordVPN",           // NordVPN client app
        "ExpressVPN",        // ExpressVPN client app
        "turnserver",        // TURN relay
        
        // System services
        "launchd",           // System launcher
        "kdc",               // Kerberos
        "identityservice",   // Apple ID
        "nesessionmanage",   // Network extension
    ]
    
    /// VPN tunnel process identifiers - these carry aggregated traffic
    /// When detected, other app traffic should be considered already counted through the tunnel
    static let vpnTunnelProcessPrefixes: [String] = [
        "ch.protonvpn",      // ProtonVPN tunnel
        "com.nordvpn",       // NordVPN tunnel
        "com.expressvpn",    // ExpressVPN tunnel
        "utun",              // Generic tunnel interface process
    ]
    
    /// Check if this is a VPN tunnel process (carries all traffic)
    static func isVPNTunnelProcess(_ name: String) -> Bool {
        for prefix in vpnTunnelProcessPrefixes {
            if name.hasPrefix(prefix) {
                return true
            }
        }
        return false
    }
    
    /// Check if a process should be excluded from internet traffic counting
    static func isLocalOnlyProcess(_ name: String) -> Bool {
        // Check exact match
        if localOnlyProcesses.contains(name) {
            return true
        }
        
        // Check prefixes for helper processes
        for localProcess in localOnlyProcesses {
            if name.hasPrefix(localProcess) {
                return true
            }
        }
        
        return false
    }
    
    /// Parse nettop CSV output
    /// Format: time,process_name,interface,state,bytes_in,bytes_out,...
    static func parseNettopOutput(_ output: String) -> [String: NettopProcessStats] {
        var results: [String: NettopProcessStats] = [:]
        let lines = output.components(separatedBy: "\n")
        
        // Find column indices from header
        var bytesInIdx = 4   // Default position
        var bytesOutIdx = 5  // Default position
        let processNameIdx = 1  // Default position (second column)
        
        for (lineIdx, line) in lines.enumerated() {
            let columns = line.components(separatedBy: ",")
            
            // First line is header
            if lineIdx == 0 {
                for (idx, col) in columns.enumerated() {
                    let cleaned = col.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if cleaned == "bytes_in" { bytesInIdx = idx }
                    else if cleaned == "bytes_out" { bytesOutIdx = idx }
                }
                continue
            }
            
            // Parse data lines
            guard columns.count > max(bytesInIdx, bytesOutIdx, processNameIdx) else { continue }
            
            // Process name is in second column (index 1), format: "ProcessName.PID"
            let processField = columns[processNameIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !processField.isEmpty else { continue }
            
            // Parse byte values
            let bytesInStr = columns[bytesInIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let bytesOutStr = columns[bytesOutIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            
            let bytesIn = UInt64(bytesInStr) ?? 0
            let bytesOut = UInt64(bytesOutStr) ?? 0
            
            // Get clean process name and extract PID
            let cleanName = cleanProcessName(processField)
            let pid = extractPid(from: processField)
            
            // Skip local-only processes (not internet traffic)
            if isLocalOnlyProcess(cleanName) {
                continue
            }
            
            // Skip VPN tunnel processes to avoid double-counting
            // The individual apps' traffic already goes through the tunnel
            if isVPNTunnelProcess(cleanName) {
                continue
            }
            
            // Skip if no data (but include processes with 0 bytes for tracking)
            // Aggregate by process name (multiple instances like Chrome helpers)
            if var existing = results[cleanName] {
                existing.bytesIn += bytesIn
                existing.bytesOut += bytesOut
                results[cleanName] = existing
            } else {
                results[cleanName] = NettopProcessStats(
                    processName: cleanName,
                    pid: pid,
                    bytesIn: bytesIn,
                    bytesOut: bytesOut
                )
            }
        }
        
        return results
    }
    
    /// Fallback: get network stats using lsof
    static func getNetworkStatsFromNetstat() -> [String: NettopProcessStats] {
        var results: [String: NettopProcessStats] = [:]
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-i", "-n", "-P"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                results = parseLsofForProcesses(output)
            }
        } catch {
            // Silently fail
        }
        
        return results
    }
    
    /// Parse lsof output to identify network-active processes
    static func parseLsofForProcesses(_ output: String) -> [String: NettopProcessStats] {
        var results: [String: NettopProcessStats] = [:]
        let lines = output.components(separatedBy: "\n")
        
        for line in lines.dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            
            let processName = String(parts[0])
            let pidStr = String(parts[1])
            let pid = pid_t(pidStr) ?? 0
            
            guard !processName.isEmpty && processName != "COMMAND" else { continue }
            
            if results[processName] == nil {
                results[processName] = NettopProcessStats(
                    processName: processName,
                    pid: pid,
                    bytesIn: 0,
                    bytesOut: 0
                )
            }
        }
        
        return results
    }
    
    /// Clean process name (remove PID suffix like "Google Chrome H.1234")
    static func cleanProcessName(_ name: String) -> String {
        // nettop format is "ProcessName.PID" 
        // Examples: "Google Chrome H.1604", "launchd.1", "mDNSResponder.174"
        let parts = name.components(separatedBy: ".")
        if parts.count >= 2, let _ = Int(parts.last!) {
            let processName = parts.dropLast().joined(separator: ".")
            // Handle truncated Chrome names
            if processName.hasPrefix("Google Chrome") {
                return "Google Chrome"
            }
            return processName
        }
        return name
    }
    
    /// Extract PID from process name if present
    static func extractPid(from name: String) -> pid_t {
        let parts = name.components(separatedBy: ".")
        if parts.count >= 2, let pid = pid_t(parts.last!) {
            return pid
        }
        return 0
    }
}
