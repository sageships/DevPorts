import SwiftUI
import AppKit

// MARK: - Port Scanner
struct PortInfo: Identifiable, Hashable {
    let id = UUID()
    let port: Int
    let pid: Int
    let process: String
    let command: String
    
    var displayName: String {
        if command.contains("next") { return "Next.js" }
        if command.contains("vite") { return "Vite" }
        if command.contains("node") { return "Node.js" }
        if command.contains("python") { return "Python" }
        if command.contains("ruby") { return "Ruby" }
        return process
    }
    
    var emoji: String {
        switch displayName {
        case "Next.js": return "▲"
        case "Vite": return "⚡"
        case "Node.js": return "🟢"
        case "Python": return "🐍"
        case "Ruby": return "💎"
        default: return "🔵"
        }
    }
}

class PortScanner: ObservableObject {
    @Published var ports: [PortInfo] = []
    
    let commonPorts = [3000, 3001, 3002, 3100, 3200, 3300, 4000, 5000, 5173, 5174, 8000, 8080, 8888]
    
    func scan() {
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [PortInfo] = []
            
            let task = Process()
            task.launchPath = "/usr/sbin/lsof"
            task.arguments = ["-iTCP", "-sTCP:LISTEN", "-n", "-P"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let lines = output.components(separatedBy: "\n")
                    for line in lines {
                        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                        if parts.count >= 9 {
                            let process = String(parts[0])
                            let pid = Int(parts[1]) ?? 0
                            let portPart = String(parts[8])
                            
                            if let colonIndex = portPart.lastIndex(of: ":") {
                                let portStr = String(portPart[portPart.index(after: colonIndex)...])
                                if let port = Int(portStr), self.commonPorts.contains(port) {
                                    let info = PortInfo(port: port, pid: pid, process: process, command: process)
                                    if !results.contains(where: { $0.port == port }) {
                                        results.append(info)
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {
                print("Error scanning ports: \(error)")
            }
            
            DispatchQueue.main.async {
                self.ports = results.sorted { $0.port < $1.port }
            }
        }
    }
    
    func killPort(_ port: Int) {
        if let info = ports.first(where: { $0.port == port }) {
            let task = Process()
            task.launchPath = "/bin/kill"
            task.arguments = ["-9", "\(info.pid)"]
            try? task.run()
            task.waitUntilExit()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.scan()
            }
        }
    }
    
    func openInBrowser(_ port: Int) {
        if let url = URL(string: "http://localhost:\(port)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Menu View
struct PortMenuView: View {
    @ObservedObject var scanner: PortScanner
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("🚀 Dev Ports")
                    .font(.headline)
                Spacer()
                Button(action: { scanner.scan() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            Divider()
            
            if scanner.ports.isEmpty {
                Text("No dev servers running")
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(scanner.ports) { port in
                    PortRowView(port: port, scanner: scanner)
                }
            }
            
            Divider()
            
            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack {
                    Text("Quit")
                    Spacer()
                    Text("⌘Q").foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 280)
        .onAppear { scanner.scan() }
    }
}

struct PortRowView: View {
    let port: PortInfo
    @ObservedObject var scanner: PortScanner
    @State private var isHovering = false
    
    var body: some View {
        HStack {
            Text(port.emoji)
            VStack(alignment: .leading, spacing: 2) {
                Text("localhost:\(port.port)")
                    .font(.system(.body, design: .monospaced))
                Text(port.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            
            if isHovering {
                Button(action: { scanner.openInBrowser(port.port) }) {
                    Image(systemName: "safari")
                }
                .buttonStyle(.plain)
                .help("Open in browser")
                
                Button(action: { scanner.killPort(port.port) }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Kill process")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovering ? Color.gray.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let scanner = PortScanner()
    var timer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Dev Ports")
            button.action = #selector(togglePopover)
        }
        
        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 300)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PortMenuView(scanner: scanner))
        
        // Auto-refresh every 10 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.scanner.scan()
        }
        
        // Initial scan
        scanner.scan()
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                scanner.scan()
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}

// MARK: - Main
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
