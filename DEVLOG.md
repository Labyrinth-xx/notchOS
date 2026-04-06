# notchOS 开发日志

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
