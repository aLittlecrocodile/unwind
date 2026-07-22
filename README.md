# Unwind 桌面端 · 打工小人

Unwind（让各位同学，压力小一点）的桌面形态：一个常驻桌角的透明桌宠。打工小人陪你分段工作（番茄钟 / 待办 / 久坐喝水提醒），压力上来时——**按住 🎙 直接跟它说话**，它会用 Unwind 智能体的能力接住你：共情对话、放一段雨声、生成安心签，重体验一键展开完整 Unwind 主窗。

## 形态

- **桌宠模式（默认）**：无边框透明窗，小人裸浮于桌面，鼠标移开自动点击穿透（不挡背后内容）；抓状态胶囊可拖动
- **对话**：按住 🎙 说话（流式 ASR → 对话 LLM → 流式 TTS，首句 1~2s），或点小人打字；回复出现在头顶气泡并开口说话
- **工作台模式**：番茄钟（25/50/90）、今日 Todo、健康提醒；休息开始时由小人接住你的喘息时刻
- **Unwind ⤢**：打开完整 Unwind 主窗（呼吸练习 / 压力粉碎机 / 声音涟漪场 / 技能矩阵）

## 目录结构

单仓库同时收纳桌面前端与决策后端，方便完整评审：

```
.
├── backend/     Unwind 后端（FastAPI + Hermes 智能体决策层，独立仓库 aLittlecrocodile/Floppy 的源码快照）
├── electron/    Electron 主进程 / preload（打工小人窗口、点击穿透、语音代理、Unwind 主窗）
├── src/         React 渲染层（桌宠交互、番茄钟工作台、语音 PTT）
└── ...
```

`backend/` 是后端仓库的源码快照（不含 `.venv`/密钥/数据库/音频产物），演进以 [aLittlecrocodile/Floppy](https://github.com/aLittlecrocodile/Floppy) 为准，这里同步便于一个仓库看到全貌。

## 运行

两个进程都要起：后端提供决策智能体、语音与音频能力，桌面端是界面。

```bash
# 1. 后端（另开一个终端，常驻）
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -e .
uvicorn floppy_backend.main:app --host 0.0.0.0 --port 8000

# 2. 桌面端
npm install
npm run dev
```

macOS 提示：若依赖来自压缩包分发，首次运行前需清除隔离属性，否则原生模块加载会被 Gatekeeper 拒绝：

```bash
xattr -dr com.apple.quarantine .
```

首次按住 🎙 说话时，系统会请求麦克风权限。后端还需要 `backend/.env`（参照 `backend/.env.example`）配置 LLM / TTS / ASR 凭证。

## 技术栈

electron-vite · Electron 39 · React 19 · TypeScript。主进程代理 Unwind 后端 HTTP/WS（无 CORS 负担），渲染层负责桌宠交互与音频播放。

> 注意：electron-vite 输出 ESM preload，`BrowserWindow` 需 `sandbox: false` 才能加载桥接（详见 `electron/main.ts` 注释）。
