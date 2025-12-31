# VibeShotMac 📸

A sleek macOS screenshot application with built-in markup capabilities, created entirely through **vibe coding** with AI assistance.

## ✨ What is VibeShotMac?

VibeShotMac is a native macOS app that enhances your screenshot workflow by providing:
- **Quick screenshot capture** with customizable overlays
- **Built-in markup editor** for annotations and edits
- **Seamless integration** with macOS screenshot workflows
- **Clean, intuitive interface** designed for efficiency

## 🤖 Created with Vibe Coding

This entire project was built using "vibe coding" - a development approach where ideas are translated into working code through natural language conversations with AI. No traditional coding tutorials, Stack Overflow searches, or documentation diving required!

### Example Initial Prompt

The project likely started with a prompt similar to this:

> *"I want to create a macOS screenshot app that can capture screens and let me quickly add annotations and markup. It should feel native to macOS and integrate well with the system. I want it to be fast and easy to use - something I'd actually want to use daily instead of the built-in screenshot tools. Can you help me build this?"*

From there, the AI helped:
- Set up the Xcode project structure
- Implement ScreenCaptureKit integration
- Create the markup editor interface
- Handle file management and user preferences
- Polish the UI/UX details

### The Vibe Coding Process

1. **Express the vision** - Describe what you want to build
2. **Iterate naturally** - Refine features through conversation
3. **Learn as you go** - Understand the code as it's created
4. **Ship quickly** - Go from idea to working app rapidly

## 🚀 How to Use VibeShotMac

### Installation

#### Via Homebrew

You can install VibeShot easily using Homebrew:

```bash
brew tap cjstremick/tap
brew install --cask vibeshot
```

#### From Source

1. **Clone the repository:**
   ```bash
   git clone https://github.com/cjstremick/VibeShotMac.git
   cd VibeShotMac
   ```

2. **Open in Xcode:**
   ```bash
   open VibeShot.xcodeproj
   ```

3. **Build and run:**
   - Select your target device (macOS)
   - Press `Cmd + R` to build and run
   - Grant necessary permissions when prompted

### Usage

1. **Launch the app** - VibeShotMac will appear in your menu bar or dock

2. **Capture screenshots:**
   - Use the app's capture interface
   - Select the area you want to screenshot
   - The capture overlay provides visual feedback

3. **Markup your screenshots:**
   - Automatic markup editor opens after capture
   - Add annotations, arrows, text, and highlights
   - Use familiar tools for quick editing

4. **Save and share:**
   - Save to your preferred location
   - Copy to clipboard for quick sharing
   - Export in various formats

### Features

- **🎯 Precision capture** - Select exactly what you want to capture
- **✏️ Rich markup tools** - Annotate with text, arrows, shapes, and highlights
- **⚡ Fast workflow** - From capture to edited screenshot in seconds
- **🍎 Native macOS feel** - Follows Apple's design guidelines
- **🔒 Privacy focused** - All processing happens locally on your Mac

## 🛠 Technical Details

- **Language:** Swift
- **Framework:** SwiftUI + AppKit
- **Capture:** ScreenCaptureKit
- **Minimum macOS:** 13.0+ (Ventura)
- **Architecture:** Native macOS application

## 📁 Project Structure

```
VibeShot/
├── VibeShotApp.swift          # App entry point
├── AppDelegate.swift          # App lifecycle management
├── QuickSCKitCapture.swift    # Screen capture functionality
├── CaptureOverlay.swift       # Capture UI overlay
├── MarkupEditorController.swift # Markup editing interface
├── MarkupModel.swift          # Markup data model
└── Assets.xcassets/           # App icons and resources
```

## 🤝 Contributing

This project was created through vibe coding, and contributions in the same spirit are welcome! Feel free to:

- **Describe new features** you'd like to see
- **Report issues** in natural language
- **Suggest improvements** to the user experience
- **Share your vibe coding experience** if you extend the project

## 📝 License

This project is open source. Feel free to use, modify, and distribute as needed.

## 🎉 About Vibe Coding

VibeShotMac demonstrates the power of vibe coding - building software by describing what you want rather than how to build it. This approach:

- **Lowers barriers** to software creation
- **Accelerates development** from idea to working product
- **Focuses on problems** rather than implementation details
- **Makes coding accessible** to more people

---

*Built with ✨ vibe coding and 🤖 AI assistance*