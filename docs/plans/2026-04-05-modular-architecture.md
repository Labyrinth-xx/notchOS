# notchOS 架构重构：模块化 + 灵动岛扩展基础

> 创建日期：2026-04-05 | 状态：✅ 已完成

## Context

notchOS v0.3 功能完整可运行，但架构上有几个卡点阻碍后续灵动岛功能的添加：
1. **Swift 所有代码挤在一个文件**（main.swift 355 行），无法独立扩展
2. **状态定义散布在 4 个文件**（Python models.py、CSS、JS、Python state_manager.py），加一个状态要改 4 处
3. **无内容模块机制**，添加新的"岛内容"（权限审批、通知气泡、Plan 预览）需要改动所有层
4. **魔法数字满天飞**（URL、时间、尺寸硬编码在各处）

本次重构目标：**不改变任何现有功能和外观**，只做结构调整，为后续灵动岛功能铺路。

---

## Phase 1：Swift 文件拆分 + 常量集中（零风险）

纯机械提取，行为完全不变。

### 目标文件结构

```
Sources/NotchConsole/
├── main.swift              ← 仅入口（~10 行）
├── AppDelegate.swift       ← 生命周期
├── Config.swift            ← NEW: 所有常量集中
├── OverlayPanel.swift      ← NSPanel 子类
├── NotchGeometry.swift     ← 屏幕检测 + 几何计算
├── NotchController.swift   ← WKWebView + hover + JS bridge
├── SoundManager.swift      ← NEW: 从 Controller 提取音效逻辑
└── MessageRouter.swift     ← NEW: 从 Controller 提取 JS 消息分发
```

### 关键变更

**Config.swift** — 集中所有魔法数字：
- `backendURL` / `uiURL`（替代硬编码 `http://127.0.0.1:23456`）
- `Timing.expandDwell` / `collapseDelay` / `soundDebounce`
- `Geometry.pillHeight` / `glowPad` / `wingWidth` / `hoverSlack`

**SoundManager.swift** — 提取自 NotchController：
- `soundMap`、`play()`、`toggleMute()`、debounce 逻辑
- NotchController 持有 `SoundManager` 实例，不再直接管音效

**MessageRouter.swift** — 提取 `userContentController(_:didReceive:)` 的 switch 分发逻辑

**NotchController.swift** — 瘦身后只负责：
- WKWebView 初始化
- hover 检测（双区域 + dwell timer）
- expand/collapse 面板动画
- 委托 SoundManager 和 MessageRouter

### 验证

```bash
swift build -c release   # 编译通过
bash scripts/bundle.sh   # 打包成功
bash scripts/launch.sh   # 运行行为与重构前完全一致
```

### 涉及文件
- 拆分：`Sources/NotchConsole/main.swift`（355 行 → 7 个文件）
- 不变：`Package.swift`（SPM 自动发现同目录 .swift 文件）

---

## Phase 2：状态定义统一（消除 4 文件同步问题）

### 核心思路

创建 `shared/states.json` 作为**唯一真相源**，Python 和 JS 都从它读取。

```
shared/
└── states.json    ← 状态定义、事件映射、动画绑定、TTL、音效触发规则
```

### states.json 结构

```json
{
  "states": {
    "idle":         { "color": "#4ade80", "priority": 9,  "dot_animation": null,     "glow": null },
    "thinking":     { "color": "#60a5fa", "priority": 4,  "dot_animation": "pulse",  "glow": "aurora-flow" },
    "working":      { "color": "#fb923c", "priority": 5,  "dot_animation": "breathe","glow": "aurora-flow" },
    ...
  },
  "events": {
    "SessionStart":      { "default_state": "idle" },
    "UserPromptSubmit":  { "default_state": "thinking" },
    "PermissionRequest": { "default_state": "notification", "content_module": "permission_dialog" },
    ...
  },
  "sounds": {
    "complete":  { "from": ["working","thinking","juggling"], "to": ["idle","sleeping","attention"] },
    "error":     { "from": ["*"], "to": ["error"] },
    "attention": { "from": ["*"], "to": ["notification"] }
  },
  "ttl": {
    "idle": 300,
    "attention": 3.6,
    "notification": 5.6
  }
}
```

### Python 侧变更

**新建 `backend/states.py`**：
- `AgentState` 枚举（替代原 string）
- `load_state_config()` 读取 `shared/states.json`（启动时加载一次，缓存）
- `default_state_for_event()` 替代原 `EVENT_TO_STATE.get()`

**修改 `backend/models.py`**：
- 删除 `EVENT_TO_STATE` 字典
- `SessionState.state` 字段类型改为 `AgentState`

**修改 `backend/state_manager.py`**：
- TTL 值从 `load_state_config()["ttl"]` 读取，不再硬编码

**修改 `backend/server.py`**：
- `receive_hook()` 调用 `default_state_for_event()` 替代 `EVENT_TO_STATE.get()`
- 新增 mount `shared/` 为静态目录（让 JS 能 fetch）

### JS 侧变更

**修改 `ui/app.js`**：
- 启动时 `fetch('/shared/states.json')` 加载配置
- `dominantState()` 用配置中的 priority 排序，不再硬编码列表
- 音效触发规则从配置读取，不再硬编码 `workingStates`/`doneStates`
- 状态颜色、动画名从配置读取

**修改 `ui/style.css`**：
- 保留所有 `@keyframes` 定义
- 删除 `#pillGlow[data-state="thinking"]` 等逐状态选择器
- 改由 JS 在状态变化时通过 `element.style.animation = ...` 动态应用

### 验证

发送各种 hook 事件，确认：pill 颜色、glow 动画、音效触发、TTL 降级行为与重构前完全一致。

### 涉及文件
- 新建：`shared/states.json`、`backend/states.py`
- 修改：`backend/models.py`、`backend/server.py`、`backend/state_manager.py`
- 修改：`ui/app.js`、`ui/style.css`

---

## Phase 3：事件路由器 + 内容模块骨架（灵动岛扩展点）

### 事件路由器

替代 server.py 中的单行 dict 查找，支持条件路由和多处理器。

**新建 `backend/event_router.py`**：

```python
class RouteResult:
    state: AgentState
    content_module: str | None = None   # 哪个 UI 模块负责渲染
    payload: dict = {}                  # 传给模块的额外数据

class EventRouter:
    def register(self, handler: EventHandler) -> None: ...
    async def route(self, event, current_session) -> RouteResult: ...
```

- `DefaultStateHandler`（priority=100）：包装现有 `default_state_for_event()`，行为不变
- 未来的 `PermissionRequestHandler`（priority=10）可拦截特定事件，返回 `content_module="permission_dialog"`

### 内容模块骨架

**Backend：`backend/content_modules/__init__.py`**

```python
class ContentModule(ABC):
    module_id: str
    def build_payload(self, event_data: dict) -> ContentPayload: ...

# Registry
def register_module(module): ...
def get_module(module_id): ...
```

**JS：`ui/modules/`**

```
ui/modules/
├── base-module.js          ← NotchModule 基类 + 注册表
└── session-status.js       ← 现有 pill/dashboard 渲染逻辑提取
```

```javascript
class NotchModule {
  get id() { ... }
  renderPill(container, data) {}
  renderDashboard(container, data) {}
  onActivate(data) {}
  onDeactivate() {}
}
```

**修改 `ui/app.js`**：
- `handleStateUpdate()` 检查 payload 是否包含 `content_module` 字段
- 有 → 委托给对应 JS 模块渲染
- 无 → 默认使用 `SessionStatusModule`

### WebSocket payload 扩展

```json
{
  "sessions": [...],
  "active_module": "session_status",     // NEW
  "module_payload": {}                   // NEW: 模块特定数据
}
```

### 验证

现有功能完全由 `DefaultStateHandler` + `SessionStatusModule` 承载，行为不变。

### 涉及文件
- 新建：`backend/event_router.py`、`backend/content_modules/__init__.py`、`backend/content_modules/session_status.py`
- 新建：`ui/modules/base-module.js`、`ui/modules/session-status.js`
- 修改：`backend/server.py`（用 router 替代直接查找）
- 修改：`backend/models.py`（SessionState 增加 content_module 字段）
- 修改：`ui/app.js`（模块加载 + 委托渲染）
- 修改：`ui/index.html`（增加 module script 引用）

---

## 执行顺序

| Phase | 内容 | 风险 | 依赖 |
|-------|------|------|------|
| 1 | Swift 文件拆分 + Config | 零 | 无 |
| 2 | states.json + Python/JS 读取 | 低-中 | 无 |
| 3 | 事件路由 + 内容模块骨架 | 低 | Phase 2 |

Phase 1 和 Phase 2 可以并行做（分别改 Swift 和 Python/JS，无交叉）。
Phase 3 依赖 Phase 2（路由器需要 states.py 的枚举）。

---

## 不做的事（明确排除）

- **不迁移到 SwiftUI**：WKWebView 方案保留，迭代速度优先
- **不实现具体灵动岛功能**：只搭骨架，权限审批/通知气泡等具体模块后续再加
- **不改 hook.py**：保持 fire-and-forget + 零依赖，双向通信后续单独做
- **不改视觉效果**：重构前后用户看到的完全一样

---

## 后续扩展路径（本次不做，仅记录）

添加一个新灵动岛功能（如"权限审批"）的步骤将变为：

1. `shared/states.json` → events 中添加 `"content_module": "permission_dialog"`
2. `backend/content_modules/permission_dialog.py` → 实现 `ContentModule`
3. `backend/event_router.py` → 注册 `PermissionRequestHandler`
4. `ui/modules/permission-dialog.js` → 实现 `NotchModule`（渲染 Allow/Deny UI）
5. 完成。**不需要改 server.py、app.js、style.css 核心代码**
