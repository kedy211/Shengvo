# 用 Claude Code 仿写 Typeless，4 小时交付一个 macOS 语音输入法

## 起因

用了大概一个月的 [Typeless](https://typeless.app/)，它是一个非常优秀的 macOS 语音输入工具——按下快捷键说话，松开就把文字粘贴到当前应用。更让我惊喜的是它内置的 LLM 文本整理能力：自动修正错字、补充标点、去除口语冗余，效果相当出色。

用了一个多月之后，我开始想：**能不能自己做一个开源版本？** 不是要替代 Typeless，而是做一个可以自由定制的替代方案——自选 ASR 引擎、自选 LLM、自定义提示词，完全掌控整个流程。

正好最近在深度使用 Claude Code，决定试一个极端挑战：**全程用 Claude Code 写代码，看多久能做出来。**

答案是：**4 小时。**

## 晟语 (Shengvo) 是什么

一个开源的 macOS 语音输入法，对标 Typeless 的核心体验：

> **按下快捷键 → 说话 → 松开 → 文字自动粘贴到当前应用**

晟语的定位不是替代 Typeless——Typeless 的体验和 LLM 整理能力已经做得相当出色。晟语是一个**开源、可自由定制**的版本，你可以：

- **自选 LLM 服务商**：豆包、GPT、DeepSeek、硅基流动……任何 OpenAI 兼容 API 都行
- **自定义系统提示词**：完全控制文本整理的行为和风格
- **自定义识别词**：添加专有名词、术语，提升识别准确率
- **应用感知**：检测当前在哪个应用里输入，自动调整 LLM 输出风格（微信聊天 vs 邮件 vs 代码编辑器）
- **历史记录**：每次输入自动保存，支持复制、粘贴、删除
- **全局快捷键**：默认 `Cmd+Shift+V`，支持 `fn` 修饰键组合

## 效果展示

### 状态栏菜单

常驻在状态栏，点击展开菜单，简洁直接：

![状态栏菜单](pics/Shengvo/settings.png)

### 通用设置

快捷键录制、开机自启动、权限管理，一目了然：

![通用设置](pics/Shengvo/设置-通用.png)

### 模型设置

配置语音识别和 LLM 的 API 密钥，系统提示词可自定义：

![模型设置](pics/Shengvo/设置-模型设置.png)

![模型设置 - 展开](pics/Shengvo/设置-模型设置2.png)

### 自定义识别词

添加专有名词、技术术语，提升识别准确率：

![自定义识别词](pics/Shengvo/自定义识别词.png)

### 历史记录

每次输入自动保存，双击可粘贴，支持复制和删除：

![历史记录](pics/Shengvo/历史记录.png)

## 技术栈

| 组件 | 技术 |
|------|------|
| 语音识别 | 火山引擎 ASR（WebSocket 实时流式） |
| 文本整理 | 任意 OpenAI 兼容 API（豆包、GPT、DeepSeek 等） |
| UI 框架 | SwiftUI |
| 开发工具 | Claude Code |

全项目约 **1000 行 Swift 代码**，从零到可用，4 小时。

## 开发过程

整个开发过程几乎完全依赖 Claude Code 完成，我只负责：

1. 描述需求（"做一个类似 Typeless 的语音输入法"）
2. 提供 API 凭证
3. 测试和反馈问题

Claude Code 负责：

- 架构设计和代码编写
- Xcode 项目配置
- 调试编译错误
- 实现录音、ASR、LLM、剪贴板粘贴的完整流程
- 写 README 和文档

中间遇到的难点（都是 Claude Code 解决的）：

- 火山引擎 ASR 的 WebSocket 协议对接
- macOS 辅助功能权限下的自动粘贴（先试 osascript，失败后 fallback CGEvent）
- `fn` 修饰键的全局监听（Carbon 不支持，改用 CGEvent tap）
- 代码签名和 Hardened Runtime 配置

## 快速上手

### 环境要求

- macOS 13.0+
- Xcode 15.0+

### 编译运行

```bash
git clone https://github.com/kedy211/Shengvo.git
cd Shengvo
open VoiceInput/VoiceInput.xcodeproj
```

Xcode 中按 `Cmd+R` 运行，首次启动会引导授权麦克风和辅助功能权限。

### 配置语音识别

1. 注册 [火山引擎控制台](https://console.volcengine.com/)
2. 进入「语音技术」→「语音识别」，创建应用
3. 获取 App ID、Access Token、Secret Key
4. 打开晟语设置 → 模型设置 → 填入三个值

### 配置 LLM（可选）

支持任何 OpenAI 兼容 API：

| 服务商 | Base URL |
|--------|----------|
| 火山引擎 Ark | `https://ark.cn-beijing.volces.com/api/v3` |
| OpenAI | `https://api.openai.com/v1` |
| DeepSeek | `https://api.deepseek.com` |
| 硅基流动 | `https://api.siliconflow.cn/v1` |

不启用 LLM 也可以正常使用，只是不会做文本整理。

## GitHub

**https://github.com/kedy211/Shengvo**

欢迎 Star、Fork、提 Issue 和 PR。如果你有好的想法或者发现了 Bug，请随时告诉我。

## 写在最后

4 小时从零到可用，这是我对 Claude Code 能力的一次验证。它不是"写个 demo 级别的玩具"，而是一个我自己每天在用的工具——录音识别、LLM 整理、自动粘贴，整个流程稳定流畅。

Typeless 是一个很棒的产品，如果你不需要那么多自定义能力，直接用它就好。晟语适合那些想要**完全掌控语音输入流程**的人——自选引擎、自定义提示词、开源可修改。

欢迎试用，欢迎提意见。
