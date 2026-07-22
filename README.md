# Unwind · 把压力，呼出去

一只常驻桌角的"打工小人" + 一个懂减压的智能体后端。它陪你分段打工（番茄钟 / 待办 / 久坐喝水提醒），压力上来时——**点一下 🎙 直接跟它说话**，Unwind 智能体会接住你：共情对话、CBT 认知重构、数息引导、放一段雨声、写一张安心签。Unwind 是减压产品：白噪音是用来"喘口气"的，不是哄睡的。

## 小人怎么玩

| 动作 | 效果 |
| --- | --- |
| 点一下 🎙 | 开始说话，再点一下结束（按住说完松手也行）；流式 ASR → 决策智能体 → 流式 TTS，首句 1~2s |
| 点小人 | 展开/收起打字面板（快捷 chips + 输入框），小人会晃一晃 |
| 按住小人或状态胶囊拖动 | 把它挪到任何地方（位移超过 5px 才算拖，不会误触点击） |
| 悬停 | 浮出工具条：**喘口气 ⤢**（完整 Unwind 主窗）· **工作台** · **躲起来**（藏 10 分钟，点 Dock 图标随时召回） |
| 鼠标移开 | 自动点击穿透，小人不挡背后的内容 |

小人自己也会活着：待命时呼吸、每 4 秒眨一次眼；番茄钟进度就填充在脚下的状态胶囊里；久坐/喝水到点时气泡自动换成提醒并浮出**一键打卡** chips；一轮专注打完，它只发一条通知、在气泡里**邀请**你喘口气——不抢屏、不弹窗，主动权在你手里。放出去的环境音会有"♪ 曲名 · 停"胶囊，随时喊停。

## 智能体技能

后端由 Hermes 决策层驱动，一句话路由到对应技能：

- **对话减压**：CBT 认知重构、数息 / 放松技巧、鼓励、安心签（comfort card）
- **仪式**：心情打分、烦恼寄存、感恩时刻、偏好记忆、睡眠定时器（真实落库，非话术）
- **声音**：环境音即点即播、按需生成、在当前音频上 remix、天气顺势荐声
- **厂内**：内搜实时问答（食堂 / 班车 / 流程类走确定性快路径，秒回并直接说出答案）

完整 Unwind 主窗（从"喘口气 ⤢"进入）还有：语音通话、跟随呼吸（麦克风驱动的呼吸球）、压力粉碎机、声音涟漪场、技能矩阵与决策轨迹可视化。

## 目录结构

单仓库同时收纳桌面前端与决策后端，方便完整评审：

```
.
├── backend/     Unwind 后端（FastAPI + Hermes 智能体决策层，独立仓库 aLittlecrocodile/Floppy 的源码快照）
├── electron/    Electron 主进程 / preload（小人窗口、点击穿透、手动拖拽、语音代理、Unwind 主窗）
├── src/         React 渲染层（桌宠 PetMode、番茄钟工作台、语音 PTT、领域模型）
└── ...
```

`backend/` 是后端仓库的源码快照（不含 `.venv`/密钥/数据库/音频产物），演进以 [aLittlecrocodile/Floppy](https://github.com/aLittlecrocodile/Floppy) 的 `unwind` 分支为准，用 `git archive` 同步。

**前后端对接契约**：桌面端只依赖 [backend/docs/frontend/desktop_integration.md](backend/docs/frontend/desktop_integration.md) 描述的接口面（`/showcase/chat`、`/voice/ws`、音频 URL 约定与降级规则）——改动任何一侧前先对照它。

## 运行

前置：Node 18+、Python 3.11+、macOS（桌宠特性按 macOS 调教）。两个进程都要起：

```bash
# 1. 后端（另开一个终端，常驻；桌面端固定连 127.0.0.1:8000）
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -e '.[dev]'
uvicorn floppy_backend.main:app --host 127.0.0.1 --port 8000

# 2. 桌面端
npm install
npm run dev
```

小人会出现在屏幕右下角、Dock 正上方。

**后端配置**（`backend/.env`，参照 `backend/.env.example`，环境变量统一 `FLOPPY_` 前缀）——不配也能跑，走本地兜底 provider：

- `FLOPPY_MINIMAX_API_KEY` — 真实 TTS / 音频生成
- `FLOPPY_HERMES_BASE_URL`、`FLOPPY_HERMES_API_STYLE`（`responses`/`chat`）— Hermes 决策端点
- `FLOPPY_QUERY_PLANNER_API_KEY` — 对话 / 脚本 LLM
- `FLOPPY_WEATHER_CITY` — 天气上下文城市（默认北京）
- 内搜：需要厂内网络 + `~/.config/uuap` 下的 ugate token

## 排障

- **小人不说话** → 先确认后端起在 8000；首次说话 macOS 会请求麦克风权限
- **`npm run dev` 报 dlopen / 签名错误** → 依赖带了下载隔离属性，`xattr -dr com.apple.quarantine .` 后重试
- **测试** → 后端 `cd backend && pytest`；桌面端 `npx tsc --noEmit`

## 技术栈

electron-vite · Electron 39 · React 19 · TypeScript · FastAPI。主进程代理后端 HTTP/WS（无 CORS 负担），渲染层负责桌宠交互与音频播放。

> 两个踩坑记录：electron-vite 输出 ESM preload，`BrowserWindow` 需 `sandbox: false` 才能加载桥接；`-webkit-app-region: drag` 在"透明+无边框+点击穿透"窗口上不可靠，拖拽是 pointer 事件 + IPC 手动实现的（详见 `electron/main.ts` 与 `src/components/PetMode.tsx` 注释）。
