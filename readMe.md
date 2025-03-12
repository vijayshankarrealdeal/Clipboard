# Clipboard History Manager

A lightweight macOS clipboard manager built with SwiftUI that captures and stores both text and image clipboard content. It runs in the background with a menu bar icon, supports a global hotkey (Command+Control+V) to bring up the main window, persists clipboard data locally, and adapts its appearance for both dark and light modes.

## Features

- **Global Hotkey:** Quickly show the clipboard history window by pressing Command+Control+V.
- **Status Bar Integration:** Access the app easily via a menu bar icon.
- **Clipboard Monitoring:** Automatically detects new text and image data on the clipboard.
- **Local Persistence:** Saves clipboard history locally as a JSON file in Application Support.
- **Dynamic Appearance:** Uses dynamic background colors for a consistent look in both dark and light modes.
- **Clear History:** A “Clear” button allows you to remove all stored clipboard items after confirming via a dialog.

## Installation

- Extract the zip `Clipboard.zip`
- Move the `Clipboard.app` to `Applications` in Finder.

## Requirements

- macOS 10.15 (Catalina) or later
- Xcode 12 or later
- Swift 5

## Build your Own

Clone the repository:

```bash
git clone https://github.com/yourusername/ClipboardHistoryManager.git
cd ClipboardHistoryManager
```

Open the project in Xcode:

```bash
open ClipboardHistoryManager.xcodeproj
```

## Usage

1. **Build and Run:** Launch the app from Xcode.
2. **Menu Bar Icon:** The app runs in the background and displays a menu bar icon.
3. **Hotkey:** Press Command+Control+V to bring up the clipboard history window.
4. **Clipboard History:** The window displays a list of clipboard items (both text and images) sorted by the most recent.
5. **Actions:** 
   - **Copy:** Re-copy an item back to the clipboard.
   - **View Full:** Open a detailed view of the clipboard content.
   - **Clear:** Remove all history (confirmation required).

## Code Overview

- **AppDelegate.swift:**  
  Sets up the global hotkey, status bar item, and manages the main window via a window controller.

- **ClipboardHistoryManager.swift:**  
  Monitors the macOS pasteboard, persists clipboard items to local storage (using JSON), and provides functionality to clear history.

- **ContentView.swift:**  
  Displays the clipboard history list and provides buttons for copying or viewing items.

- **FullTextView.swift & FullImageView.swift:**  
  Present detailed views of the clipboard content with copy and close actions.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgments

Special thanks to the macOS developer community for the inspiration and guidance in building this application.

---

This `README.md` provides an overview of the project, its features, installation instructions, and code structure, making it easier for users and contributors to understand and get started with the Clipboard History Manager.
