# notchOS 开发日志

---

## 2026-04-10 — v0.7 Dynamic Island 改造：多活动 + 双气泡 + 音乐/计时器/通知

### 完成内容

*Phase 0: 模块系统激活*
- `session-status.js` 实现完整 `renderPill()` / `renderDashboard()`
- `app.js` 委托渲染给模块，保留 glow/state 管理

*Phase 1: Activity Manager*
- 新建 `activity-manager.js`：多活动管理（claude/music/timer），动态优先级
- `handleStateUpdate()` 自动将 Claude 会话喂入 ActivityManager

*Phase 2: 双气泡 + Tab 面板*
- Swift: `NotchGeometry` 新增 `leftBubbleFrame` + `splitCollapsedFrame`（左翼区小气泡）
- Swift: `NotchController.setSplit()` + split 模式 hover 检测覆盖两个区域
- CSS: `#bubbleLeft` 左翼小气泡 + tab bar + tab pane 系统
- JS: `notchSetSplit()` bridge + tab 切换 + ActivityManager → split 联动
- 物理约束：刘海中间不可显示，气泡放在左翼（secondary）和刘海下方（primary）

*Phase 3: 音乐/媒体模块*
- `NowPlayingMonitor.swift`：dlopen MediaRemote 私有框架，3s/10s 轮询
- `music-module.js`：封面缩略图、曲名/艺人、进度条、播放控制
- 播放控制：play/pause/next/prev → Swift `MRMediaRemoteSendCommand`

*Phase 4: 计时器/番茄钟模块*
- `timer-module.js`：内建倒计时，4 种预设，localStorage 持久化
- 完成时 Swift 原生 `UNUserNotificationCenter` 通知
- 颜色随时间变化（绿→黄→红）

*Phase 5: 通知增强 + 终端跳转*
- `notification-module.js`：权限请求摘要卡片 + "Jump" 按钮
- `TerminalJump.swift`：AppleScript iTerm2 精确跳转 + 通用终端激活
- `hook.py` 新增转发 `cwd` 字段

*设置开关*
- 设置页面新增「灵动岛模块」section：音乐/计时器/通知 三个独立开关
- `shared.js` 新增 `enableMusic` / `enableTimer` / `enableNotifications` 默认值

*Code Review 修复（11 项）*
- CRITICAL: TerminalJump AppleScript 注入 → sanitizeForAppleScript()
- CRITICAL: notification-module onclick XSS → data-* + addEventListener
- HIGH: 脚本加载顺序 → activity-manager.js 提前加载
- HIGH: Timer resume 逻辑 → _resumeBase 字段
- HIGH: dlopen handle 泄漏 → deinit 中 dlclose + stop
- HIGH: JSON 转义 → JSONSerialization
- HIGH: 本地鼠标监听泄漏 → 保存 localMouseMonitor
- MEDIUM: enableNotifications 无效 → 添加检查
- MEDIUM: 废弃 API launchApplication → open(URL)
- LOW: 死变量/死代码清理
- LOW: 零尺寸图片 guard

### 关键决策
- 数据流分离：Claude→Python→WS→JS / 音乐→Swift→JS / 计时器→JS 本地
- 单 NSPanel + CSS 定位双气泡（不是两个窗口）
- 不做 GUI 权限审批，只做通知 + 跳转终端
- MediaRemote 私有框架用 dlopen（非 App Store 分发）
- 刘海物理遮挡约束：左翼放 secondary 气泡，刘海下方放 primary pill

### 遗留问题 / 下次继续
- 端到端测试（播放音乐验证双气泡 split 效果）
- 跨文件全局依赖（formatElapsed/agentBadge/AGENT_META 应移到 shared.js）
- 双 updateTabBar 调用（onChange + notchSetSplit 回调）可优化
- NowPlayingMonitor 首次 poll 在 WebView 加载完成前可能丢数据

---

## 2026-04-03 — 项目骨架完整搭建，全栈可运行

### 完成内容
- Swift 原生层：OverlayPanel、NotchGeometry、NotchController
- Python 后端：FastAPI :23456，/hook + /api/state + /ui 静态伺服
- Web UI：pill（收缩）+ dashboard（展开），轮询后端
- hook.py：零依赖 stdlib，Claude Code 钩子脚本
- scripts/launch.sh + bundle.sh：一键启动 + 打包签名

### 关键决策
- WKWebView 而非纯 SwiftUI：UI 迭代快，CSS 动画方便，热更新无需重编译
- FastAPI 而非 stdlib HTTP：Pydantic 校验，扩展方便
- hook.py 坚持零依赖：任意 Python 3 环境可运行

---

## 2026-04-04 — v0.3 视觉效果 + 交互质感

### 完成内容
- Aurora glow 光晕效果（状态驱动颜色）
- Pill 展开/收起动画（easeInEaseOut）
- 小红书风格交互质感（详情页左图右文）
- 候选自动过期机制

### 关键决策
- NSPanel level `.statusBar`：浮在所有窗口上方不抢焦点

---

## 2026-04-05 — v0.4 架构重构：模块化 + 灵动岛扩展基础

### 完成内容
- Swift main.swift（355 行）拆分为 7 个文件
- shared/states.json 唯一真相源：11 状态、15 事件、音效规则、TTL
- backend/states.py AgentState 枚举 + lru_cache 加载器
- backend/event_router.py 优先级链式路由器
- backend/content_modules/ Python ContentModule 基类 + 注册表
- ui/modules/ JS NotchModule 基类 + 注册表

### 关键决策
- states.json 而非 Python 生成 JS：JSON 原生可被两端解析，无需构建步骤
- 保留 WKWebView：内容模块作为 JS 组件可热更新

---

## 2026-04-05 — v0.5 设置面板 + 6 项可控功能

### 完成内容
- 展开面板右上角新增 ⚙ 按钮
- 6 个带开关的设置项（localStorage 持久化）：详细模式、显示代理活动、字体大小、列表高度、全屏隐藏、自动折叠

### 关键决策
- localStorage 持久化而非后端：纯前端配置，重启后端不丢失
- autoHideWhenIdle 放 JS：JS 已知 session 状态，直接调用 notifySwift("collapse")
- hideInFullscreen 放 Swift：NSPanel.collectionBehavior 只能在原生层设置

### 遗留问题
- 设置功能全部失效（根因下一版修复）

---

## 2026-04-05 — v0.6 独立设置窗口 + 设置生效链路修复

### 完成内容
- SettingsWindowController：独立 NSWindow 加载 settings.html，与 notch 弹窗完全分离
- WebView 懒加载：首次点击 ⚙ 才初始化，节省启动内存
- 修复 Critical Bug：syncSettingsUI/initSettingsListeners 引用不存在 DOM 元素 → connectWebSocket 未被调用 → 设置完全失效
- 生效链路：settingsUpdated → Swift → window.reloadSettings() → 重读 localStorage + 重绘
- 新建 shared.js：统一 notifySwift/SETTINGS_KEY/DEFAULT_SETTINGS，消除重复
- 鼠标 hover 区域修复：expandedFrame 全区域检测，消除顶部角落误收起

### 关键决策
- 设置窗口用独立 NSWindow 而非嵌入 notch 弹窗：用户体验更接近 macOS 原生设置
- shared.js 提取公共定义：两个 WebView 各自独立，无法直接共享变量，通过加载同一 JS 文件解决

### 遗留问题
- 详细模式 / 代理活动开关：需等下次 WebSocket 推送才重绘（无即时预览）
- 字体大小对 pill 无效（pill 使用固定 CSS）
- 全屏隐藏依赖 macOS 全屏切换事件，部分 app 不触发
- 设置窗口无 App icon，样式与原生设置窗口有差距

---

## 2026-04-06 — fix: 收起状态透明区域鼠标穿透

### 完成内容
- 修复收起状态下 NSPanel 透明区域（glowPad 44px）拦截鼠标事件的 bug
- 动态切换 `ignoresMouseEvents`：收起时 true（穿透），展开时 false（可交互）
- 删除 `states.json` 中未使用的 error 音效 transition + `app.js` 对应逻辑

### 关键决策
- 选择动态 `ignoresMouseEvents` 而非重写 `hitTest`：3 行改动，无副作用，光晕视觉不受影响
- hover 展开依赖全局 Mouse Monitor，不受 `ignoresMouseEvents` 影响

### 遗留问题
- v0.6 设置面板已知缺陷仍未修复（详细模式即时预览、pill 字体大小等）

---

## 2026-04-06 — feat: LaunchAgent 自启动

### 完成内容
- LaunchAgent plist（`~/Library/LaunchAgents/com.local.notchOS.plist`），登录即启动
- 启动脚本放 `~/.config/notchOS/launch.sh`，绕过 macOS TCC 对 Desktop 的限制
- 创建项目独立 `.venv/`（之前不存在），安装 fastapi + uvicorn + websockets
- `requirements.txt` 新增 `websockets>=13.0`（修复 WebSocket 404）

### 关键决策
- 脚本放 `~/.config/` 而非 `scripts/`：launchd 无法执行 `~/Desktop` 下文件（TCC 沙箱）
- 用 `.venv/bin/python3` 绝对路径代替 `source activate`：activate 与 bash strict mode 不兼容

### 遗留问题
- v0.6 设置面板已知缺陷仍未修复
