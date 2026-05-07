# 晟语 (Shengvo)

macOS 语音输入法，一键将语音转化为精准文字。

## 亮点

- **双引擎语音识别**：内置本地 Whisper 模型（离线可用），同时支持火山引擎云端 ASR，一键切换
- **LLM 文本整理**：可选启用，自动修正同音错字、补充标点、去除口语冗余。**LLM 完全可自定义** — 支持任何兼容 OpenAI API 的服务（火山引擎、OpenAI、DeepSeek 等），自由选择模型、Base URL 和系统提示词
- **应用感知**：自动识别当前输入目标应用（微信、邮件、代码编辑器、终端等），根据应用场景智能调整输出风格和语言
- **自定义识别词**：添加专有名词、术语和人名，由 LLM 在语义层面自动纠正识别错误

## 功能

- 本地 Whisper base (q8_0 量化) 引擎，CoreML + Metal 加速，低延迟离线识别
- 云端火山引擎 ASR 作为可选替代方案
- LLM 文本后处理：修正错字、补充标点、去除冗余口癖，保留原始表达风格
- 20+ 应用场景自动匹配（WeChat、钉钉、飞书、Mail、Xcode、Terminal 等）
- 通过 Accessibility API 直接向焦点输入框注入文字，不污染剪贴板
- 录音浮窗：屏幕底部居中，简洁低调
- 历史记录：自动保存，支持复制、粘贴、删除
- 全局快捷键：默认 `Cmd+Shift+V`，可自定义
- 开机自启动：可选

## 系统要求

- macOS 13.0+
- Apple Silicon Mac（本地 Whisper 推荐，Intel Mac 也可运行但推理较慢）

## 安装运行

```bash
git clone https://github.com/kedy211/Shengvo.git
cd Shengvo
open VoiceInput/VoiceInput.xcodeproj
```

在 Xcode 中选择 `VoiceInput` scheme，按 `Cmd+R` 运行。

首次运行会弹出设置向导，引导完成**麦克风权限**和**辅助功能权限**授权。

## 配置

点击状态栏图标 → **设置** 进行配置。

### 语音识别（ASR）

设置 → 模型设置 → 识别引擎：

| 引擎 | 说明 | 需要配置 |
|------|------|----------|
| **本地 Whisper**（默认） | 离线识别，无需网络，数据不上传 | 无需额外配置 |
| 云端火山引擎 | 高精度中文识别 | App ID / Access Token / Secret Key |

> 使用云端引擎需注册 [火山引擎语音识别](https://www.volcengine.com/product/speech-recognition) 并获取凭证。

### 大语言模型（LLM）— 可选

启用后，语音识别文本会经 LLM 整理优化再输入目标应用。支持任意兼容 OpenAI API 的服务：

| 服务商 | Base URL 示例 |
|--------|--------------|
| 火山引擎 Ark | `https://ark.cn-beijing.volces.com/api/v3` |
| OpenAI | `https://api.openai.com/v1` |
| DeepSeek | `https://api.deepseek.com` |
| 硅基流动 | `https://api.siliconflow.cn/v1` |
| 其他兼容服务 | 自定义 |

配置步骤：
1. 开启「启用文本整理」
2. 填写 Base URL、API Key、模型名称
3. 可调整推理强度（minimal / low / medium / high）
4. 可自定义系统提示词控制整理策略

> 未启用 LLM 时，识别原文直接输出。

### 自定义识别词

状态栏图标 → **自定义识别词**，添加专业术语、人名等。LLM 处理时会根据发音相似度自动将模糊词纠正为正确的自定义词汇。

### 快捷键

设置 → 通用 → 快捷键，点击录制后按下组合键即可。支持 `fn` 修饰键。

## 项目结构

```
VoiceInput/
├── App/                    # 应用入口
│   └── VoiceInputApp.swift # 主控制器，录音→识别→LLM→输出流程
├── Core/
│   ├── AudioRecorder.swift    # 录音管理 (16kHz mono)
│   ├── ASRService.swift       # ASR 双引擎调度 (本地 Whisper / 云端)
│   ├── LLMService.swift       # LLM API 调用 (OpenAI 兼容)
│   ├── ClipboardManager.swift # 文字注入 (AX 直注 / 剪贴板回退)
│   ├── AppLogger.swift        # 日志系统 (~/Library/Logs/Shengvo/)
│   ├── HistoryManager.swift   # 历史记录持久化
│   ├── HotKeyManager.swift    # 全局快捷键
│   └── SoundManager.swift     # 录音提示音
├── Models/
│   ├── AppConfig.swift        # 应用配置 (UserDefaults)
│   ├── ASRResponse.swift      # LLM 响应模型
│   └── HistoryEntry.swift     # 历史记录数据模型
├── Views/
│   ├── SettingsView.swift       # 设置窗口
│   ├── HistoryView.swift        # 历史记录窗口
│   ├── CustomWordsView.swift    # 自定义识别词
│   ├── RecordingOverlay.swift   # 录音浮窗
│   ├── HotKeyRecorderView.swift # 快捷键录制
│   ├── SettingComponents.swift  # 可复用设置控件
│   └── SetupView.swift          # 首次运行引导
└── Resources/
    ├── Assets.xcassets
    └── ggml-base-q8_0.bin      # Whisper base 量化模型
```

## 工作流程

```
按下快捷键 → 开始录音 → 松开快捷键
    → ASR 识别 (本地 Whisper / 云端火山引擎)
    → (可选) LLM 文本整理 + 自定义词纠错
    → 直接注入焦点输入框 → 保存历史记录
```

## 隐私说明

- 本地 Whisper 模式下，音频不离开本机
- 云端 ASR 和 LLM 模式下，仅发送必要数据
- 历史记录仅保存在本地 `~/Library/Application Support/VoiceInput/`
- API 密钥保存在本地 UserDefaults

## 开源协议

[MPL 2.0 License](LICENSE)
