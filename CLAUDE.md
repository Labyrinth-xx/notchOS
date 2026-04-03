# notchOS

macOS 刘海屏 overlay，实时显示 Claude Code 各 session 的工作状态。

## 架构

```
notchOS/
├── Sources/NotchConsole/main.swift   # Swift 原生层（NSPanel + WKWebView + 鼠标监听）
├── backend/                          # Python FastAPI 后端（:23456）
│   ├── server.py                     # 路由：/hook POST、/api/state GET、/ui static
│   ├── models.py                     # Pydantic：HookEvent、SessionState、NotchResponse
│   └── state_manager.py              # 内存 session 追踪 + TTL 清理
├── ui/                               # Web UI（WKWebView 内嵌）
│   ├── index.html
│   ├── style.css                     # 暗色主题 + 状态点动画
│   └── app.js                        # 轮询 /api/state，渲染 pill / dashboard
├── scripts/
│   ├── launch.sh                     # 一键启动后端 + open .app
│   ├── bundle.sh                     # swift build release → 打包 .app → ad-hoc 签名
│   └── hook.py                       # Claude Code hook 脚本（零依赖 stdlib）
├── resources/Info.plist
├── Package.swift
└── requirements.txt                  # fastapi>=0.115.0, uvicorn>=0.34.0
```

## 启动

```bash
cd /Users/zzx/Desktop/AI_code/notchOS

# 安装依赖（首次）
pip install -r requirements.txt

# 启动（后端 + .app）
bash scripts/launch.sh
```

## 重新编译 Swift

```bash
bash scripts/bundle.sh
```

## Hook 注册（Claude Code 集成）

在 `~/.claude/settings.json` 的 `hooks` 字段添加：

```json
{
  "hooks": {
    "PreToolUse": [
      { "command": "python3 /Users/zzx/Desktop/AI_code/notchOS/scripts/hook.py PreToolUse" }
    ],
    "PostToolUse": [
      { "command": "python3 /Users/zzx/Desktop/AI_code/notchOS/scripts/hook.py PostToolUse" }
    ],
    "UserPromptSubmit": [
      { "command": "python3 /Users/zzx/Desktop/AI_code/notchOS/scripts/hook.py UserPromptSubmit" }
    ],
    "Stop": [
      { "command": "python3 /Users/zzx/Desktop/AI_code/notchOS/scripts/hook.py Stop" }
    ]
  }
}
```

## 状态映射

| Claude Code 事件 | 显示状态 | 颜色 |
|---|---|---|
| UserPromptSubmit | thinking | 蓝 |
| PreToolUse / PostToolUse | working | 橙 |
| PostToolUseFailure | error | 红 |
| Stop | attention | 红闪 |
| SubagentStart | juggling | 紫 |
| Notification / PermissionRequest | notification | 黄 |
| PreCompact | sweeping | 蓝淡 |
| WorktreeCreate | carrying | 紫淡 |
| SessionEnd | sleeping → 移除 | — |

## 关键约束

- `hook.py` 必须保持零依赖（stdlib only），确保任意 Python 3 环境可运行
- `hook.py` timeout 设为 0.5s，不能阻塞 Claude Code 的 hook 执行
- NSPanel level 为 `.statusBar`，不能抢焦点（`canBecomeKey = false`）
- 后端固定 `127.0.0.1:23456`，Swift 层 WebView 和 hook.py 均硬编码此地址
- Web UI 修改无需重编译 Swift，直接改 `ui/` 下文件刷新即可

---

## 开发日志

### 2026-04-03 — 项目骨架完整搭建，全栈可运行

**完成内容**
- Swift 原生层：`OverlayPanel`（非激活透明面板）、`NotchGeometry`（自动检测刘海屏位置）、`NotchController`（全局 mouse monitor hover 展开/收起，WKWebView 内嵌）
- Python 后端：FastAPI on `:23456`，`/hook` 接收 Claude Code 钩子事件，`/api/state` 返回会话聚合状态，`/ui` 静态伺服 Web UI
- `StateManager`：内存 session 追踪，TTL 5分钟自动清理，从 `~/.claude/sessions/*.json` 解析项目名
- Web UI：收缩 pill（状态点 + 文字 + tool name）+ 展开 dashboard（session 卡片列表），轮询后端（收缩 2s / 展开 1s）
- `scripts/hook.py`：零依赖 stdlib，作为 Claude Code hook 脚本
- `scripts/launch.sh` / `bundle.sh`：一键启动 + 打包签名
- `.app` bundle 已编译并签名

**关键决策**
- 选择 WKWebView 而非纯 SwiftUI/AppKit：UI 迭代快，CSS 动画方便，热更新无需重编译
- 后端用 FastAPI 而非 stdlib HTTP：代码简洁，Pydantic 校验，后续扩展方便
- `hook.py` 坚持零依赖：hook 脚本需在任意 Python 3 环境运行
- 面板级别设为 `.statusBar`：浮在所有窗口之上但不干扰交互

**遗留问题 / 下次继续**
- `hook.py` 尚未注册到 `~/.claude/settings.json`
- 未做端到端连通测试（backend → hook → UI 全链路）
- 无 git 仓库（需 `git init`）
- 无测试文件
- 无 LaunchAgent（随系统自启动）

---

### 2026-04-03 — v0.2 VibeIsland 启发升级 + hover 修复

**完成内容**

*架构升级*
- `hook.py` 重构为 fire-and-forget raw socket POST（不阻塞 Claude Code，timeout 0.3s）
- 消除 `EVENT_TO_STATE` 重复：hook.py 只发 raw event name，backend 唯一做映射
- hook.py 修复 Content-Length 用字节长度（支持中文 title 不截断）

*WebSocket 实时推送（Phase 1）*
- FastAPI 新增 `/ws` WebSocket 端点，每次 hook 事件后广播状态给所有连接的 UI 客户端
- `StateManager` 增加 `broadcast()` 方法（含 set 快照防并发修改 RuntimeError）
- `app.js` 改为 WebSocket 优先 + 自动 fallback 到 5s 轮询 + 3s 自动重连

*声音通知（Phase 2）*
- Swift `NSSound` 播放 macOS 系统音效（借鉴 `notify-stop.sh` 已有方案）
  - 任务完成 → `Glass.aiff`，出错 → `Sosumi.aiff`，需注意 → `Ping.aiff`
- JS 检测状态转换（working/thinking → idle 触发 complete 音），3s 防抖
- 与已有 `notify-stop.sh` 互补：notchOS 管实时状态音，notify-stop.sh 管弹窗通知

*Session 信息丰富化（Phase 3）*
- `hook.py` 捕获首条 prompt 前 60 字作为 session `title`
- `SessionState` 增加 `title` 字段，首次 UserPromptSubmit 设置后不再覆盖
- Pill 和 Dashboard 优先显示 title，而非仅项目目录名

*Glow 光晕（Phase 3）*
- Pill `box-shadow` 随状态变色 + CSS 呼吸动画（蓝/橙/红/黄/紫）
- 余光可感知状态，不需要直接看 notch

*Confetti 庆祝（Phase 4）*
- Canvas 彩色粒子动画，dashboard 展开时任务完成触发（1-2s）

*Hover 检测修复*
- 修复原有单一矩形检测区域过大问题（260×390px 覆盖整个菜单栏区域）
- 改为双区域检测（参照 VibeIsland `_isMouseInMenuBarZone` + `_isMouseInExpandedPanel`）：
  - Zone 1（notch strip）：仅 pill 宽度，鼠标在刘海附近维持展开
  - Zone 2（content area）：展开面板内容区，完整宽度但不含菜单栏
  - 收起延迟从 0.5s 缩短到 0.15s

*几何优化*
- Collapsed pill 宽度与物理刘海缝隙精确对齐（动态计算，非硬编码 240px）
- Pill 背景 `#000` 完美融入刘海
- Hover 触发增加 0.15s 停留阈值，防止鼠标路过时误展开

**关键决策**
- 声音走 Swift NSSound 而非 HTML5 Audio：不受 WKWebView autoplay 限制，直接用系统音效无需自备文件
- 双区域 hover 检测而非单矩形：解决展开面板与菜单栏重叠导致的检测区域过大问题

**当前状态**
- GitHub: `Labyrinth-xx/notchOS`，4 个 commit，v0.2 已推送
- Hook 已注册到 `~/.claude/settings.json`（15 个事件）
- 系统完整运行中：`bash scripts/launch.sh` 启动

**遗留问题 / 下次继续**
- 无 LaunchAgent（随系统自启动）
- 无测试文件
- Hover 效果待实际使用验证（双区域方案是否够精准）
- Session title 显示：当前 title 与 project 都显示，可考虑 title 替代 project 而非并排
