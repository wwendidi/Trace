# Trace

**Turn any workflow into documentation, tutorials, and videos instantly.**

Trace is a native macOS application that watches you work and automatically generates step-by-step guides. Powered by Google Gemini, it understands your actions and transforms them into interactive overlays, HTML documentation, and fully narrated video tutorials—in seconds.

---

## 💡 The Problem

Documentation is a bottleneck in software development. Whether you're onboarding a new team member or explaining a bug fix, the process remains tedious: capture 20 screenshots, crop them, paste into a document, and annotate with "Click here, then click there." It's time-consuming, exhausting, and often outdated the moment you hit save.

---

## 🚀 The Solution

Trace runs quietly in your menu bar. Click **Record**, perform your task, then click **Stop**. Trace handles everything else:

- **Captures** high-fidelity screenshots using ScreenCaptureKit
- **Analyzes** UI context using Gemini 2.0 Flash
- **Generates** three distinct documentation formats automatically

---

## ✨ Key Features

### 1. Intelligent Workflow Analysis

Trace doesn't just record pixels—it understands context. Using Accessibility APIs to detect active windows and Gemini Vision to identify UI elements (e.g., "User clicked the 'Create' button"), Trace captures the *meaning* behind your actions. You can edit, reorder, or manually add steps using the built-in editor.

### 2. Instant Web Documentation

Need to share a guide with a colleague? Trace generates a clean, responsive HTML page with a single click. No manual formatting required.

### 3. Interactive On-Screen Guides

Stop switching between tutorial windows and your workspace. Trace's **Interactive Mode** projects a floating overlay directly onto your screen, guiding you step-by-step through the workflow in real-time.

### 4. 🎬 AI Video Generation

This is where Trace shines. The app generates a professional video tutorial from your recorded steps—without you recording any narration:

- **Scripting:** Gemini analyzes your workflow and writes a natural, cohesive voiceover script
- **Synthesis:** Trace uses Text-to-Speech to narrate the script
- **Rendering:** A custom AVFoundation engine stitches screenshots and audio into a smooth `.mp4` video
- **No Hallucinations:** Unlike generative video models, Trace uses your actual screenshots, ensuring 100% accuracy

---

## 🛠 Tech Stack

Trace is built entirely in **Swift** and optimized for macOS:

- **Google Gemini API (2.0 Flash):** Multimodal analysis for screenshot captioning and video script generation
- **ScreenCaptureKit:** High-performance, low-latency screen recording across all apps
- **Accessibility API (AXUIElement):** Window focus detection and application context
- **AVFoundation:** Custom video rendering engine that synchronizes static images with dynamic audio
- **SwiftUI & SwiftData:** Modern, responsive UI with local data persistence

---

## 📦 Installation & Setup

To run Trace locally:

### 1. Clone the repository
```bash
git clone https://github.com/yourusername/trace.git
cd trace
```

### 2. Open in Xcode
Double-click `Trace.xcodeproj`

### 3. Configure API Key
Navigate to `GeminiService.swift` and insert your Google Gemini API Key:

```swift
// GeminiService.swift
private let apiKey = "YOUR_API_KEY_HERE"
```

### 4. Build and Run
Press `Cmd + R` to launch the app

---

## 🔮 What's Next

- **Multi-language Support:** Instantly translate guides and video voiceovers into Spanish, Mandarin, and Japanese using Gemini
- **Smart Highlighting:** Automatically draw focus rings around clicked elements in video exports
- **Direct Integration:** Push documentation directly to Notion, Jira, or Confluence APIs
- **Standalone Viewer:** Enable users to view interactive tutorials without installing the full Trace app

---

## 🏆 Built For

Gemini 3 Hackathon - Demonstrating the power of Gemini's multimodal capabilities for developer productivity tools

---

## 🤝 Contributing

Contributions are welcome! Please open an issue or submit a pull request.
