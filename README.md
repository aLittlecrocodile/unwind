# Unwind 桌面端 · 打工小人

Unwind（让各位同学，压力小一点）的桌面形态：一个常驻桌角的透明桌宠。打工小人陪你分段工作（番茄钟 / 待办 / 久坐喝水提醒），压力上来时——**按住 🎙 直接跟它说话**，它会用 Unwind 智能体的能力接住你：共情对话、放一段雨声、生成安心签，重体验一键展开完整 Unwind 主窗。

## 形态

- **桌宠模式（默认）**：无边框透明窗，小人裸浮于桌面，鼠标移开自动点击穿透（不挡背后内容）；抓状态胶囊可拖动
- **对话**：按住 🎙 说话（流式 ASR → 对话 LLM → 流式 TTS，首句 1~2s），或点小人打字；回复出现在头顶气泡并开口说话
- **工作台模式**：番茄钟（25/50/90）、今日 Todo、健康提醒；休息开始时由小人接住你的喘息时刻
- **Unwind ⤢**：打开完整 Unwind 主窗（呼吸练习 / 压力粉碎机 / 声音涟漪场 / 技能矩阵）

## 运行

前置：[Unwind 后端](https://github.com/aLittlecrocodile/Floppy)需在本机 `127.0.0.1:8000` 运行（提供决策智能体、语音与音频能力）。

```bash
npm install
npm run dev
```

macOS 提示：若依赖来自压缩包分发，首次运行前需清除隔离属性，否则原生模块加载会被 Gatekeeper 拒绝：

```bash
xattr -dr com.apple.quarantine .
```

首次按住 🎙 说话时，系统会请求麦克风权限。

## 技术栈

electron-vite · Electron 39 · React 19 · TypeScript。主进程代理 Unwind 后端 HTTP/WS（无 CORS 负担），渲染层负责桌宠交互与音频播放。

> 注意：electron-vite 输出 ESM preload，`BrowserWindow` 需 `sandbox: false` 才能加载桥接（详见 `electron/main.ts` 注释）。
