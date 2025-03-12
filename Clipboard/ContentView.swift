import SwiftUI
import AppKit
import Carbon
import ServiceManagement

// MARK: - Main App Entry Point

class AppDelegate: NSObject, NSApplicationDelegate {
    var hotKeyRef: EventHotKeyRef?
    var eventHandler: EventHandlerRef?
    var statusItem: NSStatusItem?  // Status bar item
    var mainWindowController: NSWindowController?  // Dedicated window controller

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock (for a background-only app)
        NSApp.setActivationPolicy(.accessory)
        
        // Create the main window and wrap it in an NSWindowController.
        let contentView = ContentView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.contentView = NSHostingView(rootView: contentView)
        
        // Create and retain a window controller.
        mainWindowController = NSWindowController(window: window)
        
        // Set up a status bar item.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard History")
            button.action = #selector(statusItemClicked)
            button.target = self
        }
        
        registerHotKey()
        registerAppForStartup()
    }
    
    @objc func statusItemClicked() {
        showMainWindow()
    }
    
    /// Bring the dedicated main window to the front.
    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        mainWindowController?.showWindow(nil)
    }
    
    func registerHotKey() {
        // Use a let constant since hotKeyID is not mutated.
        let hotKeyID = EventHotKeyID(signature: OSType("CHVK".fourCharCodeValue), id: 1)
        let modifierFlags: UInt32 = (UInt32(controlKey) | UInt32(cmdKey))
        let keyCode: UInt32 = 9  // Keycode for "v"
        
        let status = RegisterEventHotKey(keyCode, modifierFlags, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            print("Failed to register hotkey")
        }
        
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(theEvent,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout.size(ofValue: hkID),
                              nil,
                              &hkID)
            if hkID.id == 1 {
                DispatchQueue.main.async {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.showMainWindow()
                    }
                }
            }
            return noErr
        }, 1, &eventSpec, nil, &eventHandler)
    }
    
    func registerAppForStartup() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
            } catch {
                print("Failed to register app for startup: \(error)")
            }
        } else {
            // For earlier macOS versions, consider using SMLoginItemSetEnabled with a helper app.
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
}

// Helper extension to convert a string into a FourCharCode.
extension String {
    var fourCharCodeValue: FourCharCode {
        var result: FourCharCode = 0
        if let data = self.data(using: String.Encoding.macOSRoman) {
            for (i, byte) in data.enumerated() {
                result += FourCharCode(byte) << (8 * (3 - i))
            }
        }
        return result
    }
}

// MARK: - Models

/// Represents clipboard content: text or image.
/// Updated to be Codable for persistence.
enum ClipboardContent: Codable {
    case text(String)
    case image(Data)
    
    // Convenience initializer to create image content from NSImage.
    init(nsImage: NSImage) {
        if let data = nsImage.tiffRepresentation {
            self = .image(data)
        } else {
            self = .text("")
        }
    }
    
    var asText: String? {
        if case .text(let text) = self { return text }
        return nil
    }
    
    var asImage: NSImage? {
        if case .image(let data) = self { return NSImage(data: data) }
        return nil
    }
}

/// A clipboard history item with timestamp and unique ID.
struct ClipboardItem: Identifiable, Codable {
    let id: UUID
    let date: Date
    let content: ClipboardContent
    
    init(id: UUID = UUID(), date: Date, content: ClipboardContent) {
        self.id = id
        self.date = date
        self.content = content
    }
}

// MARK: - Manager

/// Observes the macOS pasteboard, publishes new items, and persists data locally.
class ClipboardHistoryManager: ObservableObject {
    @Published var items: [ClipboardItem] = [] {
        didSet {
            saveItems()
        }
    }
    
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var ignoreNextChange = false
    private var timer: Timer?
    
    init() {
        loadItems()
        startPolling()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    /// File URL for local storage.
    private var fileURL: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("ClipboardHistory", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        }
        return folder.appendingPathComponent("clipboard_history.json")
    }
    
    /// Persist items to local storage.
    private func saveItems() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save items: \(error)")
        }
    }
    
    /// Load items from local storage.
    private func loadItems() {
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let loadedItems = try decoder.decode([ClipboardItem].self, from: data)
                items = loadedItems
            } catch {
                print("Failed to load items: \(error)")
            }
        } else {
            print("No existing file. Starting with empty history.")
            items = []
        }
    }
    
    /// Poll the pasteboard every second.
    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.checkClipboard()
        }
    }
    
    /// Check for new pasteboard content.
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        
        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            
            if ignoreNextChange {
                ignoreNextChange = false
                return
            }
            
            // Check for text.
            if let text = pasteboard.string(forType: .string), !text.isEmpty {
                let newItem = ClipboardItem(date: Date(), content: .text(text))
                DispatchQueue.main.async {
                    self.items.insert(newItem, at: 0)
                }
            }
            // Check for image.
            else if let data = pasteboard.data(forType: .tiff) {
                let newItem = ClipboardItem(date: Date(), content: .image(data))
                DispatchQueue.main.async {
                    self.items.insert(newItem, at: 0)
                }
            }
        }
    }
    
    /// Copy the given item back to the pasteboard, ignoring the resulting change.
    func copyToClipboard(item: ClipboardItem) {
        ignoreNextChange = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let data):
            pasteboard.setData(data, forType: .tiff)
        }
    }
    
    /// Clear all clipboard history.
    func clear() {
        items.removeAll()
    }
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var clipboardManager = ClipboardHistoryManager()
    @State private var selectedItem: ClipboardItem? = nil
    @State private var showingClearConfirmation = false
    
    var body: some View {
        VStack {
            HStack {
                Text("Clipboard History")
                    .font(.largeTitle)
                    .padding()
                Spacer()
                Button("Clear") {
                    showingClearConfirmation = true
                }
                .padding()
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            ScrollViewReader { proxy in
                List {
                    ForEach(clipboardManager.items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(item.date, formatter: dateFormatter)")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            switch item.content {
                            case .text(let text):
                                Text(textPreview(for: text))
                                    .lineLimit(5)
                                    .font(.body)
                            case .image(let data):
                                if let image = NSImage(data: data) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 200)
                                }
                            }
                            
                            HStack {
                                Button("Copy") {
                                    clipboardManager.copyToClipboard(item: item)
                                }
                                Button("View Full") {
                                    selectedItem = item
                                }
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        .padding(.vertical, 4)
                        .id(item.id)
                    }
                }
                .listStyle(PlainListStyle())
                .onReceive(clipboardManager.$items) { newItems in
                    if let firstID = newItems.first?.id {
                        DispatchQueue.main.async {
                            withAnimation {
                                proxy.scrollTo(firstID, anchor: .top)
                            }
                        }
                    }
                }
                .sheet(item: $selectedItem) { item in
                    switch item.content {
                    case .text(_):
                        FullTextView(item: item, manager: clipboardManager)
                    case .image(_):
                        FullImageView(item: item, manager: clipboardManager)
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        // Set a dynamic background that adapts to dark/light mode.
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Clear All History?", isPresented: $showingClearConfirmation) {
            Button("Clear", role: .destructive) {
                clipboardManager.clear()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to clear all clipboard history?")
        }
    }
    
    private func textPreview(for text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.prefix(5).joined(separator: "\n")
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }
}

// MARK: - Full Views

struct FullTextView: View {
    let item: ClipboardItem
    @ObservedObject var manager: ClipboardHistoryManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Full Text")
                .font(.headline)
                .padding(.vertical)
            Divider()
            ScrollView {
                if case .text(let text) = item.content {
                    Text(text)
                        .padding()
                }
            }
            .frame(maxHeight: .infinity)
            HStack {
                Button("Copy") {
                    manager.copyToClipboard(item: item)
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
            .padding()
        }
        .frame(width: 600, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct FullImageView: View {
    let item: ClipboardItem
    @ObservedObject var manager: ClipboardHistoryManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            Text("Full Image")
                .font(.headline)
                .padding(.vertical)
            Divider()
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                if case .image(let data) = item.content, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
            HStack {
                Button("Copy") {
                    manager.copyToClipboard(item: item)
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
            .padding()
        }
        .frame(width: 600, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    ContentView()
}
