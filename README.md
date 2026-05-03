# 晟语 (Shengvo)

 macOS 语音输入法，支持语音识别 + 大模型文本整理，一键将语音转化为精准文字。

## 功能特性

- **语音识别**：基于火山引擎 ASR，高精度中文语音转文字
- **LLM 文本整理**（可选）：自动修正同音错字、补充标点、去除口语冗余，保留原始表达风格
- **应用感知**：根据当前输入目标应用（微信、邮件、代码编辑器等）自动调整输出风格
- **自定义识别词**：添加专有名词、术语，提升识别准确率
- **历史记录**：自动保存每次输入记录，支持复制、粘贴、删除
- **全局快捷键**：默认 `Cmd+Shift+V`，可在设置中自定义
- **开机自启动**：可选

## 系统要求

- macOS 13.0+
- Xcode 15.0+（编译）

## 编译运行

```bash
git clone https://github.com/your-username/voice-input.git
cd voice-input
open VoiceInput/VoiceInput.xcodeproj
```

在 Xcode 中选择 `VoiceInput` scheme，按 `Cmd+R` 运行。

首次运行需要授权**麦克风权限**和**辅助功能权限**（用于自动粘贴）。应用会弹出设置向导引导完成授权。

## 配置说明

应用首次运行后，点击状态栏图标 → **设置** 进行配置。

### 1. 语音识别（ASR）— 必填

使用 [火山引擎语音识别](https://www.volcengine.com/product/peech-recognition) 服务。

| 字段 | 说明 | 获取方式 |
|------|------|----------|
| App ID | 应用标识 | 火山引擎控制台 → 语音技术 → 语音识别 → 创建应用 |
| Access Token | 访问令牌 | 同上，应用详情页获取 |
| Secret Key | 密钥 | 同上，应用详情页获取 |

**操作步骤：**
1. 注册并登录 [火山引擎控制台](https://console.volcengine.com/)
2. 进入「语音技术」→「语音识别」
3. 创建新应用，获取 App ID、Access Token、Secret Key
4. 将三个值填入晟语设置 → 模型设置 → 语音识别 (ASR)

### 2. 大语言模型（LLM）— 可选

启用后，语音识别的原始文本会经过 LLM 整理（修正错字、补充标点、去除口语冗余），再输入到目标应用。

支持任何兼容 OpenAI API 格式的服务，如：

| 服务商 | Base URL 示例 | 说明 |
|--------|--------------|------|
| 火山引擎 Ark | `https://ark.cn-beijing.volces.com/api/v3` | 豆包系列模型 |
| OpenAI | `https://api.openai.com/v1` | GPT 系列 |
| DeepSeek | `https://api.deepseek.com` | DeepSeek 系列 |
| 硅基流动 | `https://api.siliconflow.cn/v1` | 多种开源模型 |

**配置步骤：**
1. 在设置 → 模型设置 → 大语言模型 (LLM) 中开启「启用文本整理」
2. 填写 Base URL、API Key、模型名称
3. 可调整「推理强度」（minimal/low/medium/high）
4. 可自定义「系统提示词」来控制文本整理风格

> **提示**：如果不启用 LLM，语音识别的原始文本会直接粘贴到目标应用。

### 3. 自定义识别词

点击状态栏图标 → **自定义识别词**，添加专有名词、人名、术语等，提升识别准确率。

### 4. 快捷键

在设置 → 通用 → 快捷键 中点击录制，按下你想要的组合键。

支持 `fn` 修饰键（如 `fn+V`）。

## 项目结构

```
VoiceInput/
├── App/                    # 应用入口
│   └── VoiceInputApp.swift # 主控制器，录音→识别→LLM→粘贴流程
├── Core/
│   ├── AudioRecorder.swift    # 录音管理
│   ├── ASRService.swift       # 火山引擎 ASR 调用
│   ├── LLMService.swift       # LLM API 调用
│   ├── ClipboardManager.swift # 剪贴板 & 自动粘贴
│   ├── HistoryManager.swift   # 历史记录持久化
│   └── HotKeyManager.swift    # 全局快捷键
├── Models/
│   ├── AppConfig.swift        # 应用配置（UserDefaults 存储）
│   ├── ASRResponse.swift      # ASR & LLM 响应模型
│   └── HistoryEntry.swift     # 历史记录数据模型
├── Views/
│   ├── SettingsView.swift       # 设置窗口
│   ├── HistoryView.swift        # 历史记录窗口
│   ├── CustomWordsView.swift    # 自定义识别词
│   ├── RecordingOverlay.swift   # 录音悬浮窗
│   ├── HotKeyRecorderView.swift # 快捷键录制组件
│   └── SetupView.swift          # 首次运行引导
└── Resources/
    └── Assets.xcassets
```

## 工作流程

```
按下快捷键 → 开始录音 → 松开快捷键
    → 火山引擎 ASR 语音识别
    → （可选）LLM 文本整理
    → 复制到剪贴板 + 自动粘贴到目标应用
    → 同时保存到历史记录
```

## 隐私说明

- 所有音频数据仅用于语音识别，不会被存储
- 历史记录仅保存在本地 `~/Library/Application Support/VoiceInput/`
- API 密钥保存在本地 UserDefaults，不会上传到任何第三方服务器

## 开源协议

[MPL 2.0 License](LICENSE)
