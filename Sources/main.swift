import SwiftUI
import AppKit

// MARK: - Port Scanner
struct PortInfo: Identifiable, Hashable {
    let id = UUID()
    let port: Int
    let pid: Int
    let process: String
    let command: String
    
    var autoName: String {
        let lower = command.lowercased()
        if lower.contains("next") { return "Next.js" }
        if lower.contains("vite") { return "Vite" }
        if lower.contains("astro") { return "Astro" }
        if lower.contains("remix") { return "Remix" }
        if lower.contains("nuxt") { return "Nuxt" }
        if lower.contains("svelte") { return "SvelteKit" }
        if lower.contains("webpack") { return "Webpack" }
        if lower.contains("parcel") { return "Parcel" }
        if lower.contains("esbuild") { return "esbuild" }
        if lower.contains("turbo") { return "Turbopack" }
        if lower.contains("node") { return "Node.js" }
        if lower.contains("python") || lower.contains("uvicorn") || lower.contains("gunicorn") { return "Python" }
        if lower.contains("flask") { return "Flask" }
        if lower.contains("django") { return "Django" }
        if lower.contains("fastapi") { return "FastAPI" }
        if lower.contains("ruby") || lower.contains("rails") { return "Ruby" }
        if lower.contains("php") || lower.contains("artisan") { return "PHP" }
        if lower.contains("go") { return "Go" }
        if lower.contains("rust") || lower.contains("cargo") { return "Rust" }
        if lower.contains("java") || lower.contains("spring") { return "Java" }
        if lower.contains("ControlCe") { return "ControlCenter" }
        return process
    }
    
    func emoji(for name: String) -> String {
        switch name.lowercased() {
        case "next.js": return "▲"
        case "vite": return "⚡"
        case "node.js": return "🟢"
        case "python", "flask", "django", "fastapi": return "🐍"
        case "ruby": return "💎"
        case "go": return "🐹"
        case "rust": return "🦀"
        case "java": return "☕"
        case "php": return "🐘"
        case "astro": return "🚀"
        case "controlcenter": return "⚙️"
        default: return "🔵"
        }
    }
}

// MARK: - Name Storage
class PortNameStore: ObservableObject {
    @Published var customNames: [Int: String] = [:]
    
    private let key = "DevPorts.customNames"
    
    init() {
        load()
    }
    
    func load() {
        if let data = UserDefaults.standard.dictionary(forKey: key) as? [String: String] {
            customNames = Dictionary(uniqueKeysWithValues: data.compactMap { key, value in
                if let port = Int(key) { return (port, value) }
                return nil
            })
        }
    }
    
    func save() {
        let data = Dictionary(uniqueKeysWithValues: customNames.map { ("\($0.key)", $0.value) })
        UserDefaults.standard.set(data, forKey: key)
    }
    
    func getName(for port: PortInfo) -> String {
        return customNames[port.port] ?? port.autoName
    }
    
    func setName(for port: Int, name: String?) {
        if let name = name, !name.isEmpty {
            customNames[port] = name
        } else {
            customNames.removeValue(forKey: port)
        }
        save()
    }
}

class PortScanner: ObservableObject {
    @Published var ports: [PortInfo] = []
    
    // Common dev server ports only
    let devPorts: Set<Int> = [
        // Web dev
        3000, 3001, 3002, 3003, 3004, 3005,
        3100, 3200, 3300,
        4000, 4001, 4200, 4300,
        5000, 5001, 5173, 5174, 5175, 5500,
        8000, 8001, 8002, 8080, 8081, 8888, 8443,
        9000, 9001, 9090,
        // Databases (optional, useful to see)
        5432,  // PostgreSQL
        3306,  // MySQL
        6379,  // Redis
        27017, // MongoDB
    ]
    
    // Processes to always exclude (system/IDE junk)
    let excludedProcesses: Set<String> = [
        "ControlCe", "Control Center", "controlcenter",
        "rapportd", "Rapport",
        "Cursor",  // IDE internals
        "Code Helper", "Code - Insiders",
        "TechSmith",
        "stable",  // SD WebUI uses specific ports anyway
        "mongod",  // Covered by port list if needed
    ]
    
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
                            
                            // Skip system/IDE processes
                            if process == "launchd" || process == "systemd" { continue }
                            if self.excludedProcesses.contains(process) { continue }
                            
                            if let colonIndex = portPart.lastIndex(of: ":") {
                                let portStr = String(portPart[portPart.index(after: colonIndex)...])
                                if let port = Int(portStr),
                                   self.devPorts.contains(port) {
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
    @ObservedObject var nameStore: PortNameStore
    @State private var copied = false
    
    func copyAllPorts() {
        let text = scanner.ports.map { port in
            let name = nameStore.getName(for: port)
            return "localhost:\(port.port) - \(name) (\(port.process))"
        }.joined(separator: "\n")
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("🚀")
                Text("Dev Ports")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                
                if !scanner.ports.isEmpty {
                    Button(action: copyAllPorts) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(copied ? .green : .secondary)
                    .help("Copy all ports")
                }
                
                Button(action: { scanner.scan() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            
            Divider()
            
            if scanner.ports.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No dev servers running")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(scanner.ports) { port in
                            PortRowView(port: port, scanner: scanner, nameStore: nameStore)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            
            Divider()
            
            // Quit button
            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack {
                    Text("Quit")
                        .font(.system(size: 13))
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 280)
        .onAppear { scanner.scan() }
    }
}

struct PortRowView: View {
    let port: PortInfo
    @ObservedObject var scanner: PortScanner
    @ObservedObject var nameStore: PortNameStore
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editingName = ""
    
    var displayName: String {
        nameStore.getName(for: port)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            
            // Port info
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("localhost:\(port.port)")
                        .font(.system(size: 13, design: .monospaced))
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(port.process)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                if isEditing {
                    TextField("Name", text: $editingName, onCommit: {
                        nameStore.setName(for: port.port, name: editingName)
                        isEditing = false
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
                } else {
                    Text(displayName)
                        .font(.system(size: 11))
                        .foregroundColor(.blue.opacity(0.8))
                        .onTapGesture(count: 2) {
                            editingName = displayName
                            isEditing = true
                        }
                }
            }
            
            Spacer()
            
            // Action buttons - always visible but subtle
            HStack(spacing: 4) {
                Button(action: { scanner.openInBrowser(port.port) }) {
                    Image(systemName: "safari")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(isHovering ? .blue : .secondary.opacity(0.5))
                .help("Open in browser")
                
                Button(action: { scanner.killPort(port.port) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(isHovering ? .red : .secondary.opacity(0.5))
                .help("Kill process")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isHovering ? Color.primary.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            scanner.openInBrowser(port.port)
        }
        .contextMenu {
            Button("Open in Browser") {
                scanner.openInBrowser(port.port)
            }
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("http://localhost:\(port.port)", forType: .string)
            }
            Button("Copy with Name") {
                let text = "localhost:\(port.port) - \(displayName) (\(port.process))"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            Divider()
            Button("Rename...") {
                editingName = displayName
                isEditing = true
            }
            Button("Reset Name") {
                nameStore.setName(for: port.port, name: nil)
            }
            Divider()
            Button("Kill Process", role: .destructive) {
                scanner.killPort(port.port)
            }
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let scanner = PortScanner()
    let nameStore = PortNameStore()
    var timer: Timer?
    var eventMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Dev Ports")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 260, height: 200)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PortMenuView(scanner: scanner, nameStore: nameStore)
        )
        
        // Close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
        
        // Auto-refresh every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.scanner.scan()
        }
        
        // Initial scan
        scanner.scan()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        timer?.invalidate()
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                scanner.scan()
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
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
