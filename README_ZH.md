# QuickTranslate

[English](README.md) | **简体中文**

一款超轻量（约 600 KB）、**完全免费且离线运行**的 macOS 原生菜单栏划词翻译工具，支持 **英语 ↔ 简体中文**。纯 Swift 编写，基于 macOS 原生端侧框架，无需 API Key、无需订阅、无任何第三方依赖。

---

## 核心功能

- **全局鼠标划词翻译**：在任意 App 或浏览器中用鼠标选中英文单词或句子 → 光标旁弹出小巧的毛玻璃翻译图标，点击即刻翻译。
- **全局快捷键**：
  - `⌥ D`（`Option + D`）：直接翻译当前选中文本（自动识别语言方向：`英文 → 简体中文` 或 `简体中文 → 英文`）。
  - `⌥ S`（`Option + S`）：**截图 OCR 翻译**——框选图片、视频、菜单或任意无法选中的文字，使用 Apple Vision 本地离线识别并翻译。
- **100% 免费 & 本地离线**：
  - **Apple 端侧翻译**（`Translation` 框架）：本地离线完成整句与段落翻译，响应迅速且保护隐私。
  - **macOS 内置词典**：选中单个英文单词或短语时，自动附带系统词典释义。
  - **原生英文朗读**：弹窗内点击 `🔊` 按钮即可朗读英文发音。
- **贴心交互细节**：
  - 原生毛玻璃悬浮卡片，支持一键复制、方向切换、窗口置顶（`📌`）和手动编辑。
  - 鼠标划词时自动忽略纯中文内容，日常操作不打扰。
  - 优先使用 macOS 辅助功能读取选区；在浏览器 / Electron 应用中自动启用剪贴板无痕备份与恢复，不破坏你原本复制的内容。

---

## 运行要求

- **macOS 15.0 (Sequoia) 及以上版本**（支持 Apple Silicon 与 Intel）
- 从源码编译需要安装 **Apple 命令行开发者工具**：
  ```bash
  xcode-select --install
  ```

---

## 编译与安装

```bash
git clone https://github.com/AlexLin0803/QuickTranslate.git
cd QuickTranslate
bash build.sh
cp -R QuickTranslate.app /Applications/
open /Applications/QuickTranslate.app
```

---

## 首次使用权限设置

1. **辅助功能权限** *（用于读取鼠标划词与 `⌥D` 快捷键）*：
   - 点击顶部菜单栏的 QuickTranslate 图标 → **Grant Accessibility Permission…**
   - 在 **系统设置 → 隐私与安全性 → 辅助功能** 中打开 **QuickTranslate** 开关。
2. **录屏与系统录音权限** *（仅在使用 `⌥S` 截图 OCR 翻译时需要）*：
   - 首次按下 `⌥S` 时，系统会自动弹出授权提示。
3. **离线语言包** *（首次翻译时由系统自动提示下载）*：
   - 第一次翻译时，macOS 会弹出苹果原生弹窗提示下载免费的 **英语 / 简体中文** 离线翻译包，下载完成后即可完全离线使用。
4. **开机自启动** *（可选）*：
   - 打开 **系统设置 → 通用 → 登录项与扩展 → 登录时打开 → 点击 `+` → 选择应用程序中的 QuickTranslate**。

---

## 项目结构

```text
├── Sources/
│   ├── main.swift                       # 程序入口（菜单栏常驻应用）
│   ├── AppDelegate.swift                # 菜单栏图标、菜单配置与功能调度
│   ├── SelectionMonitor.swift           # 全局鼠标拖选与双击监听
│   ├── TextCaptureService.swift         # 辅助功能读取 + 无痕剪贴板回退
│   ├── HotKeyManager.swift              # 全局快捷键注册（⌥D、⌥S）
│   ├── FloatingTriggerPanel.swift       # 光标旁的悬浮触发小图标
│   ├── TranslationCardView.swift        # SwiftUI 毛玻璃翻译卡片与 Apple Translation
│   ├── TranslationPopoverPanel.swift    # 不抢占焦点的悬浮窗口面板
│   ├── DictionaryAndSpeechService.swift # macOS 内置词典查询与语音朗读
│   ├── OCRManager.swift                 # 交互式截屏与 Apple Vision 离线 OCR
│   └── SettingsStore.swift              # 偏好设置持久化
├── build.sh                             # 零依赖 swiftc 编译与签名脚本
├── README.md
├── README_ZH.md
└── LICENSE
```

---

## 开源协议

基于 [MIT](LICENSE) 协议开源。
