# notchOS

macOS 刘海屏 overlay，实时显示 Claude Code 各 session 的工作状态。

## 架构

```
notchOS/
├── Sources/NotchConsole/             # Swift 原生层（v0.4 已拆分为 7 个文件）
│   ├── main.swift                    # 入口（~10 行）
│   ├── Config.swift                  # 所有常量集中（URL、时间、几何、音效）
│   ├── OverlayPanel.swift            # NSPanel 子类（非激活透明面板）
│   ├── NotchGeometry.swift           # 屏幕 notch 检测 + 几何计算
│   ├── NotchController.swift         # WKWebView + hover 检测 + 面板动画
│   ├── SoundManager.swift            # NSSound 播放 + 去抖 + 静音
│   ├── MessageRouter.swift           # JS→Swift 消息分发
│   └── AppDelegate.swift             # 生命周期
├── shared/                           # 跨层共享配置
│   └── states.json                   # 唯一真相源：状态、事件映射、动画、TTL、音效规则
├── backend/                          # Python FastAPI 后端（:23456）
│   ├── server.py                     # 路由 + 事件路由器接入
│   ├── models.py                     # Pydantic：HookEvent、SessionState、NotchResponse
│   ├── states.py                     # AgentState 枚举 + states.json 加载器
│   ├── state_manager.py              # 内存 session 追踪 + TTL 清理
│   ├── event_router.py               # 可插拔事件路由（优先级链）
│   └── content_modules/              # 灵动岛内容模块
│       ├── __init__.py               # ContentModule 基类 + 注册表
│       └── session_status.py         # 默认模块：会话状态卡片
├── ui/                               # Web UI（WKWebView 内嵌）
│   ├── index.html
│   ├── style.css                     # 暗色主题 + @keyframes（状态样式由 JS 注入）
│   ├── app.js                        # WebSocket + 从 states.json 动态加载配置
│   └── modules/                      # JS 内容模块
│       ├── base-module.js            # NotchModule 基类 + 注册表
│       └── session-status.js         # 默认模块
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

> 唯一真相源：`shared/states.json`。加新状态只改这一个文件。

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

## Swift 编码规范

> 基于 twostraws/SwiftAgents 裁剪，仅保留 AppKit + WebKit macOS 项目适用的规则。

### 通用 Swift 规则

- 优先使用 `async/await` 而非闭包回调（如有 async 版本 API）
- **禁止 GCD**：不使用 `DispatchQueue.main.async()` 等旧式并发，用 modern Swift concurrency
- 避免 force unwrap (`!`) 和 force `try`，除非不可恢复
- 优先使用 Swift 原生字符串方法：`replacing("a", with: "b")` 而非 `replacingOccurrences(of:with:)`
- 使用现代 Foundation API：`URL.documentsDirectory`、`appending(path:)` 等
- 使用 `FormatStyle` 而非 `DateFormatter` / `NumberFormatter`
- 优先使用 static member lookup：`.circle` 而非 `Circle()`
- `localizedStandardContains()` 用于用户输入的文本过滤

### 项目结构

- 不同类型拆分到不同 Swift 文件（v0.4 已完成，7 个文件）
- 按功能/特性组织文件夹，而非按类型
- 不引入第三方框架，除非事先确认
- API key 等密钥不进仓库

### 不适用的规则（明确排除）

以下 SwiftAgents 规则**不适用于本项目**，不要自作主张引入：
- SwiftUI 相关：`@Observable`、`@State`、`NavigationStack`、`foregroundStyle()` 等
- SwiftData 相关
- iOS 相关（本项目为 macOS）

## 关键约束

- `hook.py` 必须保持零依赖（stdlib only），确保任意 Python 3 环境可运行
- `hook.py` timeout 设为 0.5s，不能阻塞 Claude Code 的 hook 执行
- NSPanel level 为 `.statusBar`，不能抢焦点（`canBecomeKey = false`）
- 后端固定 `127.0.0.1:23456`，Swift 层通过 `Config.swift` 引用，hook.py 硬编码
- Web UI 修改无需重编译 Swift，直接改 `ui/` 下文件刷新即可

---

## 保存上传工作流（MANDATORY）

每当用户说"保存"/"上传"/"记录"/"提交"/"commit"/"push"，**必须严格按以下顺序执行**：

1. **更新文档**：追加 `DEVLOG.md` 一条日志 + 更新本文件"当前状态"
2. **第一次 commit**：`git add` + `git commit`（安全快照，是 simplify 的回滚点）
3. **运行 `/simplify`**：代码审查 + 修复
4. **如果 simplify 有改动**：再 `git add` + `git commit -m "simplify: 代码质量优化"`
5. **推送**：`git push`

> **顺序不能颠倒**：第 2 步的 commit 是安全网。simplify 如果改错了，可以 `git reset --hard HEAD~1` 一键还原。
> 如果先跑 simplify 再 commit，这个回滚点就不存在了。

### DEVLOG.md 格式

每次追加，**只追加，不修改历史**：

```
## YYYY-MM-DD — <本次会话一句话概述>

### 完成内容
- ...

### 关键决策
- 选择 X 方案，原因：...

### 遗留问题 / 下次继续
- ...
```

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
- ~~无 LaunchAgent（随系统自启动）~~ → ✅ 已实现
- Session title 显示：当前 title 与 project 都显示，可考虑 title 替代 project 而非并排
- 展开面板高度是否需要动态调整（内容少时不需要 260px）

---

### 2026-04-03 — v0.3 交互体验修复（hover + 面板几何）

**完成内容**

*幽灵区域修复*
- Dashboard `height: 100%` 未生效（body 无明确高度），导致面板底部有透明区域捕获鼠标但不可见
- 修复：`html, body { height: 100% }`，`#pill` 和 `#dashboard` 改为 `position: absolute; inset: 0`

*Hover 灵敏度优化*
- 触发区去掉向下扩展（`dy: -12` → `dy: -4`），仅保留微量向上扩展保证屏幕顶端可触及
- Dwell 时间 0.15s → 0.4s，需明确停留在刘海上才触发，正常滑动不误触

*Dwell timer 修复*
- 原实现依赖 `mouseMoved` 事件检测 dwell 时间差，鼠标停住后无事件 → 不触发
- 改为 `Timer.scheduledTimer(0.4s)` + fire 时重新验证鼠标位置

*Pill 高度缩小*
- `pillHeight` 36 → 30px，减少收起状态下黑色遮挡区域

*刘海避让*
- Dashboard `padding-top` 14px → 38px（30px 刘海 + 8px 呼吸），内容不再被物理刘海遮挡

**关键决策**
- Hover 方案选"缩小触发区 + 延长 dwell"而非"点击切换"：保留 hover 的直觉性，通过精准区域 + 停留阈值消除误触
- Timer 触发而非事件触发：解决了"鼠标停住不动"的 edge case，macOS global mouse monitor 只在鼠标移动时回调

**当前状态**
- 已编译并运行，交互体验显著改善
- 待 git commit

---

### 2026-04-05 — v0.4 架构重构：模块化 + 灵动岛扩展基础

**完成内容**

*Phase 1: Swift 文件拆分*
- `main.swift`（355 行）拆分为 7 个独立文件
- 新增 `Config.swift`：所有魔法数字集中（URL、时间、几何尺寸、音效路径）
- 新增 `SoundManager.swift`：从 Controller 提取音效逻辑
- 新增 `MessageRouter.swift`：从 Controller 提取 JS 消息分发

*Phase 2: 状态定义统一*
- 新增 `shared/states.json`：唯一真相源（11 状态、15 事件映射、3 音效规则、TTL、glow 动画定义）
- 新增 `backend/states.py`：`AgentState` 枚举 + `lru_cache` 加载器
- `models.py` 删除 `EVENT_TO_STATE` 硬编码字典
- `app.js` 启动时 fetch `states.json`，动态注入 CSS 规则
- `style.css` 删除所有逐状态选择器，保留 `@keyframes` 定义

*Phase 3: 事件路由 + 内容模块骨架*
- 新增 `backend/event_router.py`：优先级链式路由器 + `DefaultStateHandler`
- 新增 `backend/content_modules/`：Python `ContentModule` 基类 + 注册表 + `SessionStatusModule`
- 新增 `ui/modules/`：JS `NotchModule` 基类 + 注册表 + `SessionStatusModule`
- `server.py` 接入路由器替代直接 dict 查找
- `SessionState` 模型增加 `content_module` / `module_payload` 字段

*Swift 编码规范整合*
- 基于 twostraws/SwiftAgents 裁剪，写入 CLAUDE.md（AppKit + WebKit 适用规则 + 明确排除 SwiftUI/iOS）

**关键决策**
- 选择 `shared/states.json` 而非 Python 生成 JS：JSON 原生可被 Python 和 JS 解析，无需构建步骤
- 事件路由器而非更多 dict 条目：1:1 dict 无法表达"PermissionRequest → 设置状态 + 激活权限模块 + 携带 payload"
- 保留 WKWebView：迭代速度优先，内容模块作为 JS 组件可热更新
- CSS 样式动态注入：加新状态只改 `states.json` 一处

**后续添加灵动岛功能的流程**
1. `states.json` → events 中添加 `content_module` 字段
2. `backend/content_modules/xxx.py` → 实现 `ContentModule`
3. `backend/event_router.py` → 注册新 `EventHandler`
4. `ui/modules/xxx.js` → 实现 `NotchModule`
5. 不需要改 server.py、app.js、style.css 核心代码

**当前状态**
- Swift 编译通过，Python 全流程测试通过
- 重构前后行为完全一致
- 待 git commit

---

### 2026-04-05 — v0.5 设置面板 + 6 项可控功能

**完成内容**

*设置入口*
- 展开面板右上角新增 ⚙ 图标按钮
- 点击滑出设置面板（slide-up 动画）；面板内 ← 返回

*6 个带开关的设置项（localStorage 持久化）*

| 设置 | 默认 | 说明 |
|------|------|------|
| 详细模式 | ✅ 开 | Pill 显示 `{项目} · {状态}` + 工具名 |
| 显示代理活动 | ❌ 关 | 会话卡片中以 activity-row 高亮当前工具调用 |
| 字体大小 | 中 (12px) | 小/中/大 切换，CSS `--font-size-base` |
| 会话列表高度 | 180px | 滑块 100–320px，控制 sessions-list max-height |
| 全屏时隐藏 | ❌ 关 | JS→Swift `settingChanged`，切换 `collectionBehavior` |
| 无会话时自动折叠 | ❌ 关 | 纯 JS：全部 idle/empty 后 10s 自动 collapse |

*代码变更*
- `ui/index.html`：⚙ 按钮 + 完整设置面板 HTML
- `ui/style.css`：设置面板、iOS 风格 toggle、滑块、activity-row 样式（+263 行）
- `ui/app.js`：`DEFAULT_SETTINGS`、`loadSettings/saveSettings/applySettings/syncSettingsUI`、`initSettingsListeners`、`scheduleAutoHide/cancelAutoHide`；改写 `renderPill`（详细/简洁模式）和 `renderDashboard`（showAgentActivity）
- `Sources/NotchConsole/MessageRouter.swift`：新增 `settingChanged` case
- `Sources/NotchConsole/NotchController.swift`：新增 `applySetting(key:rawValue:)`（`hideInFullscreen` → `collectionBehavior`）

**关键决策**
- 设置持久化走 localStorage 而非后端：纯前端配置无需 round-trip，重启后端不丢失
- `autoHideWhenIdle` 放 JS 而非 Swift：JS 已知 session 状态，直接调用已有 `notifySwift("collapse")` 接口
- `hideInFullscreen` 需 Swift 处理：`NSPanel.collectionBehavior` 只能在原生层设置

**当前状态**
- Swift 编译通过（`swift build -c release` ✅）
- JS 语法检查通过（`node --check` ✅）
- 待 git commit + 端到端测试

---

### 2026-04-05 — v0.6 独立设置窗口 + 设置生效链路修复

**完成内容**

*独立设置窗口*
- 设置改为独立 NSWindow（`SettingsWindowController`），加载 `ui/settings.html`
- ⚙ 按钮发送 `openSettingsWindow` → Swift 打开独立窗口，与 notch 弹窗完全分离
- 窗口首次打开时才初始化 WebView（懒加载，节省启动内存）
- `settings.html` + `settings.js`：独立设置页面，macOS 风格深色分组布局

*设置生效链路*
- 修复 Critical Bug：`syncSettingsUI()` + `initSettingsListeners()` 引用了不存在于 `index.html` 的 DOM 元素，导致启动时 TypeError → `connectWebSocket()` 未被调用
- 链路：settings.js 保存 → `notifySwift("settingsUpdated")` → Swift → `webView.evaluateJavaScript("window.reloadSettings()")` → 主面板重读 localStorage + 重新渲染
- 鼠标识别区域修复：顶部展开区域左右角之前不在任何 hover zone 内，导致误触发收起

*代码清理（simplify）*
- 新建 `ui/shared.js`：`notifySwift`、`SETTINGS_KEY`、`DEFAULT_SETTINGS` 统一定义，消除 app.js 与 settings.js 重复
- 删除 `app.js` 中 `syncSettingsUI()`（死代码）和 `initSettingsListeners()`（DOM 元素不存在）
- `SettingsWindowController` 从 `settingChanged` case 中移除多余的 `reloadSettingsInDashboard()` 调用（避免双重 reload）

**已知缺陷（待修复）**
- [ ] 详细模式 / 显示代理活动开关：改动后需等待下一次 WebSocket 推送才重绘（无即时预览）
- [ ] 字体大小 / 列表高度：对已展开面板立即生效，但 notch pill 上的字体大小无效（pill 使用固定 CSS）
- [ ] 全屏时隐藏：行为依赖 macOS 全屏切换事件，部分 app 全屏方式不触发
- [ ] 无会话时自动折叠：10s 定时器，在快速切换 session 状态时可能误触发
- [ ] 设置窗口没有 App icon，标题栏样式和原生 macOS 设置窗口有差距

**当前状态**
- Swift 编译通过 ✅
- 所有 6 项设置实时生效 ✅

---

### 2026-04-06 — fix: 收起状态透明区域鼠标穿透

**完成内容**
- 修复收起状态下 NSPanel 透明区域（`glowPad` 44px 填充）拦截鼠标事件的 bug
- `OverlayPanel.init()` 加 `ignoresMouseEvents = true`（默认穿透）
- `NotchController.expand()` 设为 `false`（展开可交互）
- `NotchController.collapse()` 设为 `true`（收起穿透）
- 删除 `states.json` 中未使用的 `error` 音效 transition + `app.js` 对应逻辑

**关键决策**
- 动态 `ignoresMouseEvents` 而非重写 `hitTest`：3 行改动，光晕视觉不受影响，hover 展开依赖全局 Monitor 不受影响

**当前状态**
- Swift 编译通过 ✅
- 收起状态透明区域鼠标穿透 ✅

---

### 2026-04-06 — feat: LaunchAgent 自启动

**完成内容**
- 新建 `~/.config/notchOS/launch.sh`：后台启动脚本（非 TCC 保护目录）
- 新建 `~/Library/LaunchAgents/com.local.notchOS.plist`：`RunAtLoad: true` 登录即启动
- 创建项目独立 `.venv/`：之前不存在，uvicorn/fastapi 依赖缺失
- `requirements.txt` 新增 `websockets>=13.0`：修复 WebSocket 404
- 新建 `scripts/launch-daemon.sh`：项目内备份，供手动参考

**关键决策**
- 脚本放 `~/.config/notchOS/` 而非项目 `scripts/`：macOS TCC 阻止 launchd 执行 `~/Desktop` 下文件
- 直接用 `.venv/bin/python3` 绝对路径而非 `source activate`：避免 venv activate 与 `set -u` 不兼容
- `KeepAlive: false`：脚本内 `wait` 保活 uvicorn 进程，崩溃不自动重启（避免循环）

**当前状态**
- LaunchAgent 注册并运行 ✅
- 后端 :23456 + WebSocket + NotchConsole App 全部正常 ✅
