import SwiftUI
import AppKit
import Carbon
import ServiceManagement

// MARK: - Main App Entry Point

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var hotKeyRef: EventHotKeyRef?
    var eventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock. Alternatively, set LSUIElement to YES in Info.plist.
        NSApp.setActivationPolicy(.accessory)
        
        registerHotKey()
        registerAppForStartup()
    }
    
    func registerHotKey() {
        // Define a hotkey ID.
        var hotKeyID = EventHotKeyID(signature: OSType("CHVK".fourCharCodeValue), id: 1)
        // Use Command + Control modifiers; keycode for "v" is 9.
        let modifierFlags: UInt32 = (UInt32(controlKey) | UInt32(cmdKey))
        let keyCode: UInt32 = 9
        
        let status = RegisterEventHotKey(keyCode, modifierFlags, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            print("Failed to register hotkey")
        }
        
        // Install an event handler to capture the hotkey event.
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
                // Bring the app to the foreground.
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first {
                    window.makeKeyAndOrderFront(nil)
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
enum ClipboardContent {
    case text(String)
    case image(NSImage)
}

/// A clipboard history item with timestamp and unique ID.
struct ClipboardItem: Identifiable {
    let id = UUID()
    let date: Date
    let content: ClipboardContent
}

// MARK: - Manager

/// Observes the macOS pasteboard and publishes new items.
class ClipboardHistoryManager: ObservableObject {
    @Published var items: [ClipboardItem] = []
    
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var ignoreNextChange = false
    private var timer: Timer?
    
    init() {
        startPolling()
    }
    
    deinit {
        timer?.invalidate()
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
        
        // If there's a new pasteboard change
        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            
            // Skip if we just copied something ourselves
            if ignoreNextChange {
                ignoreNextChange = false
                return
            }
            
            // Check for text
            if let text = pasteboard.string(forType: .string), !text.isEmpty {
                let newItem = ClipboardItem(date: Date(), content: .text(text))
                DispatchQueue.main.async {
                    self.items.insert(newItem, at: 0) // newest at top
                }
            }
            // Check for image
            else if let data = pasteboard.data(forType: .tiff),
                    let image = NSImage(data: data) {
                let newItem = ClipboardItem(date: Date(), content: .image(image))
                DispatchQueue.main.async {
                    self.items.insert(newItem, at: 0) // newest at top
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
        case .image(let image):
            if let tiffData = image.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
            }
        }
    }
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var clipboardManager = ClipboardHistoryManager()
    
    // Store the currently selected item for the sheet
    @State private var selectedItem: ClipboardItem? = nil
    
    var body: some View {
        // ScrollViewReader to auto-scroll to newest item
        ScrollViewReader { proxy in
            List {
                ForEach(clipboardManager.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        // Timestamp
                        Text("\(item.date, formatter: dateFormatter)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        // Preview (5 lines for text, thumbnail for images)
                        switch item.content {
                        case .text(let text):
                            Text(textPreview(for: text))
                                .lineLimit(5)
                                .font(.body)
                        case .image(let image):
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                        }
                        
                        // Action buttons
                        HStack {
                            Button("Copy") {
                                clipboardManager.copyToClipboard(item: item)
                            }
                            Button("View Full") {
                                selectedItem = item // Show full text or image in sheet
                            }
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.vertical, 4)
                    .id(item.id) // For auto-scroll
                }
            }
            .listStyle(PlainListStyle())
            .navigationTitle("Clipboard History")
            
            // Auto-scroll to newest item
            .onReceive(clipboardManager.$items) { newItems in
                if let firstID = newItems.first?.id {
                    DispatchQueue.main.async {
                        withAnimation {
                            proxy.scrollTo(firstID, anchor: .top)
                        }
                    }
                }
            }
            
            // Sheet that shows the selected item in full
            .sheet(item: $selectedItem) { item in
                switch item.content {
                case .text(_):
                    FullTextView(item: item, manager: clipboardManager)
                case .image(_):
                    FullImageView(item: item, manager: clipboardManager)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    /// Returns only the first 5 lines of text.
    private func textPreview(for text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let firstFive = lines.prefix(5)
        return firstFive.joined(separator: "\n")
    }
    
    /// Date formatter for timestamps
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }
}

// MARK: - Full Views

/// Shows the full text with Copy and Close buttons.
struct FullTextView: View {
    let item: ClipboardItem
    @ObservedObject var manager: ClipboardHistoryManager
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("\tFull Text")
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
    }
}

/// Shows the full image with Copy and Close buttons.
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
                if case .image(let image) = item.content {
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
    }
}

#Preview {
    ContentView()
}
