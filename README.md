# 晟语 (Shengvo)

macOS 语音输入法，一键将语音转化为精准文字。

## 亮点

- **三引擎语音识别 + 故障转移**：内置本地 Whisper 模型（离线可用），同时支持火山引擎云端 ASR 和阿里云 Qwen-ASR，一键切换。主引擎失败时自动按用户指定的顺序切换备选引擎，最终可兜底至 Apple Speech 系统语音识别
- **LLM 文本整理**：可选启用，自动修正同音错字、补充标点、去除口语冗余。失败时自动回退为 ASR 原文输出。**LLM 完全可自定义** — 支持任何兼容 OpenAI API 的服务（火山引擎、OpenAI、DeepSeek 等），自由选择模型、Base URL 和系统提示词
- **模块化提示词系统**：提示词拆分为可组合的角色/任务/规则/输出块，支持多模式扩展（polish / translate / qa），热词注入、输出清理（剥离 `<think>` 块和废话前缀）
- **多轮上下文**：可选启用，连续口述时自动将前几轮内容作为上下文传入 LLM，提升语义连贯性
- **应用感知**：自动识别当前输入目标应用（微信、Mail、代码编辑器、终端等），按 10+ 种应用场景智能调整输出风格
- **自定义识别词**：添加专有名词、术语和人名，由 LLM 在语义层面自动纠正识别错误
- **热键双模式**：支持切换模式（按一下开始、再按一下结束）和按住模式（按住录音、松开结束），支持 Fn / Right ⌘ / Left ⌥ / Right ⌥ 单键触发
- **处理进度条**：录音结束后浮窗自动变为两阶段进度条（ASR→LLM），基于轮询进度和历史耗时估算，替换无意义的转圈等待
- **重新粘贴快捷键**：默认 Option+V，一键重新粘贴上一条 LLM 整理后的文本，解决光标位置错误导致粘贴丢失的问题。菜单栏同步显示，快捷键可自定义
- **液态玻璃风格**：全局 ultraThinMaterial 磨砂玻璃材质，参考新版 macOS 设计

## 功能

- 本地 Whisper base (q8_0 量化) 引擎，CoreML + Metal 加速，低延迟离线识别
- 云端火山引擎 ASR 作为可选替代方案
- 阿里云 Qwen-ASR (Qwen3-ASR-Flash) 云端引擎，SOTA 中文识别准确率，支持 28 语种+16 方言
- Apple Speech 系统语音识别作为最终兜底引擎
- ASR 故障转移链：用户可配置 fallback 顺序，主引擎失败自动切换
- LLM 文本后处理：修正错字、补充标点、去除冗余口癖，保留原始表达风格
- LLM 故障转移：API 调用失败时自动使用 ASR 原文
- 模块化提示词架构：角色定义 / 任务描述 / 通用规则 / 输出约束 四层可组合块
- 多轮上下文：保留最近 N 轮口述内容（可配置 1-5 轮），LLM 按前文语境理解代词和未完整句子
- 输出清理：自动剥离 `<think>...</think>` 推论块和常见 LLM 废话前缀
- 10+ 精简应用场景映射（Xcode / 微信 / Mail / 终端 等），其余走通用 fallback
- 用户自定义系统提示词覆盖模式（独立 Tab 编辑）
- 通过 Accessibility API 直接向焦点输入框注入文字，不污染剪贴板
- 录音浮窗：屏幕底部居中，液态玻璃 + 彩色微光效果，处理阶段自动切换为进度条
- 声纹可视化：5 条音频波形在浮窗内随音量动态变化
- 历史记录：SQLite 持久化存储，记录 ASR 引擎、ASR/LLM 耗时数据，支持复制、粘贴、删除
- 历史导出：导出为文件夹（CSV 索引 + WAV 音频 + TXT 文本），含完整耗时信息
- 全局快捷键：支持组合键和单键（Fn / Right ⌘ / Left ⌥ / Right ⌥），可自定义模式
- 重新粘贴：独立快捷键（默认 Option+V），一键重新粘贴上一条结果到正确位置，菜单栏快捷入口
- 开机自启动：可选

## 系统要求

- macOS 13.0+
- Apple Silicon Mac（本地 Whisper 推荐，Intel Mac 也可运行但推理较慢）

## 安装运行

```bash
git clone https://github.com/kedy211/Shengvo.git
cd Shengvo
# 方式一：使用 XcodeGen 生成项目
xcodegen generate --spec Shengvo/project.yml
# 方式二：直接打开已有项目
open Shengvo/Shengvo.xcodeproj
```

在 Xcode 中选择 `Shengvo` scheme，按 `Cmd+R` 运行。

首次运行会弹出设置向导，引导完成**麦克风权限**和**辅助功能权限**授权。

## 配置

点击状态栏图标 → **设置** 进行配置。

### 语音识别（ASR）

设置 → 语音识别：

| 引擎 | 说明 | 需要配置 |
|------|------|----------|
| **本地 Whisper**（默认） | 离线识别，无需网络，数据不上传 | 无需额外配置 |
| 云端火山引擎 | 高精度中文识别 | App ID / Access Token / Secret Key |
| 阿里云 Qwen-ASR | SOTA 中文识别，28 语种+16 方言，标点+噪声过滤 | API Key (百炼) |

> 使用云端引擎需注册对应服务并获取凭证：
> - 火山引擎：[语音识别](https://www.volcengine.com/product/speech-recognition)
> - 阿里云 Qwen：[百炼大模型平台](https://bailian.console.aliyun.com/)

#### 故障转移

语音识别 → 故障转移，可添加备选引擎并调整顺序（Whisper / 火山引擎 / Qwen / Apple Speech）。主引擎失败时按顺序自动切换。Apple Speech 作为最终兜底可单独开关。

### 大语言模型（LLM）— 可选

设置 → LLM 处理：

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
3. 可设置跳过 LLM 的字数阈值（短文本直接输出原文）
4. 可调整推理强度（minimal / low / medium / high）
5. 系统提示词可在独立的「系统提示词」Tab 中查看和编辑

> 未启用 LLM 时，识别原文直接输出。提示词架构参考 [OpenLess](https://github.com/nicepkg/openless-beta) 项目。

#### 多轮上下文

设置 → LLM 处理 → 多轮上下文：

- 开启后，连续口述时 LLM 会拿到前 N 轮的历史内容作为语义上下文（代词指代、未完整句子等）
- 可配置保留 1-5 轮，默认 3 轮。每轮额外消耗 tokens

### 系统提示词

设置 → 系统提示词：

- 默认使用模块化提示词自动生成，可在此 Tab 预览完整内容
- 启用自定义后可编辑完整的系统提示词，覆盖默认行为
- 热词自动注入到提示词末尾

### 自定义识别词

状态栏图标 → **自定义识别词**，添加专业术语、人名等。LLM 处理时会根据发音相似度自动纠正转写错误。

### 快捷键

设置 → 通用 → 快捷键：

**录音热键：**
- **切换模式**：按一下开始录音，再按一下结束
- **按住模式**：按住不放录音，松开结束
- **组合键**：录制按下组合键（如 Cmd+Shift+V）即可
- **单键**：支持 Fn / Right ⌘ / Left ⌥ / Right ⌥ 作为独立热键

**重新粘贴热键：**
- 默认 `Option+V`，一键重新粘贴上一条结果
- 支持自定义组合键录制
- 状态栏菜单同步显示：重新粘贴上一条 ⌥V

## 项目结构

```
Shengvo/
├── App/                    # 应用入口
│   └── ShengvoApp.swift    # 主控制器，录音→识别→LLM→输出流程
├── Core/
│   ├── AudioRecorder.swift          # 录音管理 (16kHz mono)
│   ├── ASRService.swift             # ASR 多引擎调度 + 故障转移链
│   ├── AppleSpeechRecognizer.swift  # Apple Speech 兜底引擎
│   ├── LLMService.swift             # LLM API 调用 (OpenAI 兼容，多轮上下文)
│   ├── PromptManager.swift          # 模块化提示词管理器 (角色/任务/规则/输出块 + 输出清理)
│   ├── ConversationContext.swift    # 多轮上下文存储器 (FIFO, 保留最近 N 轮)
│   ├── ClipboardManager.swift       # 文字注入 (AX 直注 / 剪贴板回退)
│   ├── AppLogger.swift              # 日志系统 (~/Library/Logs/Shengvo/)
│   ├── HistoryManager.swift         # 历史记录 (SQLite 持久化 + JSON 自动迁移)
│   ├── ExportService.swift          # 历史记录导出 (CSV + WAV + TXT)
│   ├── HotKeyManager.swift          # 全局快捷键 (Carbon + CGEvent Tap, 双模式 + 单键)
│   ├── ModelManager.swift           # Whisper 模型下载管理
│   ├── SoundManager.swift           # 录音提示音
│   └── SQLite/
│       └── DatabaseQueue.swift      # SQLite 线程安全封装 (系统 libsqlite3)
├── Models/
│   ├── AppConfig.swift              # 应用配置 (UserDefaults, Codable 迁移)
│   ├── ASRResponse.swift            # LLM 响应模型
│   └── HistoryEntry.swift           # 历史记录数据模型 (含耗时/引擎字段)
├── Views/
│   ├── SettingsView.swift           # 设置窗口 (7 Tab 侧边栏 + 液态玻璃)
│   ├── SettingComponents.swift      # 可复用设置控件 (Stepper / Toggle / TextField 等)
│   ├── RecordingOverlay.swift       # 录音浮窗 (液态玻璃 + 声纹 + 处理进度条)
│   ├── HotKeyRecorderView.swift     # 快捷键录制 (录音键 + 重新粘贴键)
│   └── SetupView.swift              # 首次运行引导
└── Resources/
    └── Assets.xcassets
```

## 工作流程

```
按下录音快捷键 → 开始录音（浮窗显示声纹） → 松开快捷键（或再次按下）
    → ASR 识别（主引擎 → 故障转移链 → Apple Speech 兜底，浮窗显示进度条）
    → (可选) LLM 文本整理 + 多轮上下文感知 + 热词纠错 + 输出清理（进度条持续推进）
    → LLM 失败则输出 ASR 原文
    → 直接注入焦点输入框 → 保存历史记录 (SQLite, 含耗时追踪)
    → 可选：按 Option+V 重新粘贴上一条到正确位置
```

## 隐私说明

- 本地 Whisper 模式下，音频不离开本机
- Apple Speech 兜底模式下，音频发送至 Apple 服务器（可在设置中关闭）
- 云端 ASR 和 LLM 模式下，仅发送必要数据
- 历史记录仅保存在本地 `~/Library/Application Support/Shengvo/` (SQLite 数据库)
- API 密钥保存在本地 UserDefaults

## 版本历史

### 1.4.0
- 处理进度条：录音结束后的浮窗替换 spinner 为两阶段进度条（ASR 基于轮询真实进度 / LLM 基于历史耗时估算），进度填满整个浮窗 pill
- 声纹增强：录音浮窗内 WaveView 波形条 4→5 条，加宽，视觉更饱满
- 重新粘贴快捷键：独立热键（默认 Option+V），一键重新粘贴上一条 LLM 整理后的文本到正确位置
- 重新粘贴可配置：设置页新增快捷键录制器，菜单栏同步显示当前快捷键

### 1.3.0
- WebSocket 流式 ASR 引擎：边录音边识别，实时显示部分结果
- 历史记录：JSON → SQLite 迁移，新增 ASR/LLM 耗时追踪和引擎标签
- 历史导出：支持导出为文件夹（CSV 索引 + WAV 音频 + TXT 文本）
- ASR 故障转移链：用户可配置 fallback 顺序，新增 Apple Speech 兜底引擎
- LLM 故障转移：API 失败时自动回退为 ASR 原文输出
- 热键双模式：切换模式 + 按住模式，新增 Fn / Right ⌘ / Left ⌥ / Right ⌥ 单键
- 设置面板拆分：7 Tab（通用 / ASR / LLM / 提示词 / 热词 / 历史 / 关于）
- 液态玻璃 UI：全局 ultraThinMaterial 磨砂材质 + 彩色微光 Recording Overlay

### 1.1.0
- 模块化提示词架构：拆分为角色/任务/规则/输出四层可组合块，支持多模式扩展
- 多轮上下文支持：连续口述时自动传入前 N 轮历史，提升语义连贯性
- 输出清理：自动剥离 `<think>` 推论块和常见 LLM 废话前缀
- 应用映射精简：35+ → 13 条精确匹配，其余走通用 fallback
- 用户自定义提示词覆盖模式（默认隐藏，高级用户可开启）
- 设置 UI 改进：Stepper 控件替代自定义 ± 按钮，修复数值输入不生效问题
- 关于页面版本号从 Info.plist 动态读取

### 1.0.3
- 新增阿里云 Qwen-ASR 引擎 (Qwen3-ASR-Flash)
- 项目重命名为 Shengvo，Bundle ID 改为 com.shengvo.app

## 开源协议

[MPL 2.0 License](LICENSE)
