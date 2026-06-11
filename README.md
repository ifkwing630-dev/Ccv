# CCV — Cross-Device Clipboard Sync

一键将手机剪贴板内容同步到电脑，反之亦然。同一 WiFi 下，复制即同步。

## 项目背景

在日常工作中，经常需要在手机和电脑之间传递文本——验证码、链接、笔记、ChatGPT 回答等等。微信"文件传输助手"需要多步操作，第三方云剪贴板需要登录且隐私风险高。

CCV 在局域网内直连，不经过任何云服务器，复制的内容只有你和你的设备知道。

## 核心功能

- **双向实时同步**：手机复制 → 电脑粘贴，电脑复制 → 手机粘贴
- **零配置连接**：输入同一个房间号即可配对，无需输入 IP
- **跨应用通用**：微信、ChatGPT、Chrome、备忘录等均支持
- **后台保活**：Android 前台 Service + WAKE_LOCK，切后台不断连
- **自动重连**：网络断开后指数退避自动恢复，无需手动操作

## 支持平台

| 平台 | 技术栈 | 
|------|--------|
| Android | Flutter + Kotlin |
| Windows | Node.js + WebSocket |

> iOS / macOS / Linux 暂不支持，欢迎贡献。

## 使用方法

### 电脑端

```bash
cd windows
npm install
npm start
```

浏览器自动打开 → 输入房间号（如 `1234`）→ 点击「创建房间」

### 手机端

安装 APK → 打开 Ccv → 输入相同房间号 → 点击「加入房间」

之后手机复制任何文本，电脑直接 Ctrl+V 即可粘贴；电脑 Ctrl+C 复制，手机也能直接粘贴。

## 安装方法

### 手机端（Android）

从 [Releases](https://github.com/your-username/ccv/releases) 下载最新 `ccv-vX.X.X.apk`，直接安装。

### 电脑端（Windows）

**方式一：直接运行（推荐）**

从 [Releases](https://github.com/your-username/ccv/releases) 下载 `ClipboardSync.exe`，双击运行。

**方式二：从源码运行**

```bash
cd windows
npm install
npm start
```

### 从源码构建 Android APK

```bash
cd android
flutter pub get
flutter build apk --release
```

## 技术架构

```
手机复制文本
    ↓
Android ClipboardManager 变化
    ├─ OnPrimaryClipChangedListener（ChatGPT / Chrome）
    └─ AccessibilityService（微信 / 特殊 App）
    ↓
WebSocket → 电脑剪贴板
```

## 已知限制

- **Android 14 后台剪贴板读取受限**：系统禁止后台应用读取剪贴板内容。CCV 通过弹出同步按钮让用户一键触发前台读取来绕过此限制。
- **仅支持文本**：图片、文件等二进制内容暂不支持。
- **需要同一 WiFi**：手机和电脑必须在同一局域网内。
- **vivo / OPPO 需手动配置**：需在系统设置中开启自启动、关闭电池优化、开启悬浮窗权限。
- **微信不走标准 Clipboard API**：通过 AccessibilityService 关键词匹配兜底覆盖。

## 未来计划

- [ ] 支持 iOS / macOS
- [ ] 端到端加密
- [ ] 图片同步
- [ ] 多设备同时连接
- [ ] 独立桌面客户端（Electron）

## 开源协议

MIT License — 详见 [LICENSE](LICENSE)
