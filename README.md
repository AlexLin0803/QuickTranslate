# QuickTranslate

**English** | [简体中文](README_ZH.md)

A lightweight (~600 KB), **100% free & offline** native macOS menu bar translation app for **English ↔ Simplified Chinese (简体中文)**, built with pure Swift and Apple's on-device frameworks—zero API keys, zero subscriptions, zero third-party dependencies.

---

## Features

- **Select Text Anywhere**: Highlight any English word or sentence in any app or browser → click the unobtrusive floating translate icon near your cursor.
- **Global Shortcuts**:
  - `⌥ D` (`Option + D`) — Instantly translate selected text in any app (auto-detects direction: `EN → 简体中文` or `简体中文 → EN`).
  - `⌥ S` (`Option + S`) — **Screenshot OCR Translate**: drag a box over any image, video, or unselectable UI to extract and translate text completely offline via Apple Vision.
- **100% Free & On-Device**:
  - **Apple Translation** (`Translation` framework) for fast, private offline sentence & paragraph translation.
  - **macOS Native Dictionary** (`CoreServices`) for automatic single-word definitions.
  - **Native English Pronunciation** (`AVFoundation`) via the built-in `🔊` button.
- **Thoughtful UX**:
  - Frosted-glass floating HUD card with 1-click Copy, Direction Swap, Pin (`📌`), and Edit.
  - Auto-skips text that's already in Chinese during mouse selection so it never gets in your way.
  - Accessibility-first text capture with a smart clipboard save/restore fallback for Electron apps, browsers, and PDFs (never overwrites your clipboard).

---

## Requirements

- **macOS 15.0 (Sequoia) or later** (Apple Silicon or Intel)
- **Apple Command Line Tools** (to compile from source):
  ```bash
  xcode-select --install
  ```

---

## Build & Install

```bash
git clone https://github.com/AlexLin0803/QuickTranslate.git
cd QuickTranslate
bash build.sh
cp -R QuickTranslate.app /Applications/
open /Applications/QuickTranslate.app
```

---

## First-Time macOS Permissions

1. **Accessibility** *(required for reading mouse selection & `⌥D`)*:
   - Click the QuickTranslate menu bar icon → **Grant Accessibility Permission…**
   - Turn on **QuickTranslate** in **System Settings → Privacy & Security → Accessibility**.
2. **Screen Recording** *(only needed for Screenshot OCR `⌥S`)*:
   - macOS prompts automatically the first time you press `⌥S`.
3. **Offline Language Pack** *(one-time free Apple download)*:
   - On your very first translation, macOS displays a native Apple dialog to download the offline **English ↔ Simplified Chinese** pack.
4. **Auto-Start at Login** *(optional)*:
   - **System Settings → General → Login Items & Extensions → Open at Login → `+` → QuickTranslate**.

---

## Project Structure

```text
├── Sources/
│   ├── main.swift                       # App entry point (menu bar accessory app)
│   ├── AppDelegate.swift                # Menu bar, wiring, permissions & actions
│   ├── SelectionMonitor.swift           # Global mouse drag / double-click detection
│   ├── TextCaptureService.swift         # Accessibility + clipboard-safe capture
│   ├── HotKeyManager.swift              # Global Carbon hotkeys (⌥D, ⌥S)
│   ├── FloatingTriggerPanel.swift       # Tiny floating cursor button
│   ├── TranslationCardView.swift        # SwiftUI frosted-glass HUD + Apple Translation
│   ├── TranslationPopoverPanel.swift    # Non-activating floating NSPanel
│   ├── DictionaryAndSpeechService.swift # macOS Dictionary + AVSpeechSynthesizer
│   ├── OCRManager.swift                 # Interactive screencapture + Apple Vision OCR
│   └── SettingsStore.swift              # Persistent menu bar preferences
├── build.sh                             # Zero-dependency swiftc build & codesign script
├── README.md
├── README_ZH.md
└── LICENSE
```

---

## License

[MIT](LICENSE)
