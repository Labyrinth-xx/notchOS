# Vibe Island 竞品深度研究报告

> 调研日期：2026-04-05
> 用途：作为 notchOS 项目的完整技术参考，覆盖产品功能、实现原理、代码架构、Hook 协议、UI 渲染技术
> 信息来源：官网、GitHub 62 个 Release Notes、开源竞品源码（Claude Island + my-code-island）、Claude Code 源码分析、macOS Notch 开源项目

---

## 目录

1. [产品概览](#1-产品概览)
2. [核心功能详解](#2-核心功能详解)
3. [Claude Code Hook 完整协议](#3-claude-code-hook-完整协议)
4. [StatusLine JSON Schema](#4-statusline-json-schema)
5. [权限审批双向通信机制](#5-权限审批双向通信机制)
6. [macOS Notch 区域 UI 渲染技术](#6-macos-notch-区域-ui-渲染技术)
7. [终端检测与跳转实现](#7-终端检测与跳转实现)
8. [开源竞品架构对比](#8-开源竞品架构对比)
9. [notchOS 现有架构 vs 差距分析](#9-notchos-现有架构-vs-差距分析)
10. [性能优化编年史](#10-性能优化编年史)
11. [竞品对比总表](#11-竞品对比总表)
12. [参考链接](#12-参考链接)
13. [设置页面完整功能清单](#13-设置页面完整功能清单截图分析-2026-04-05)
14. [notchOS 可用性评估 + 优先级建议](#14-notchos-可用性评估--优先级建议)
15. [开源竞品深度调研（2026-04-09 补充）](#15-开源竞品深度调研2026-04-09-补充)

---

## 1. 产品概览

| 项目 | 内容 |
|------|------|
| 名称 | Vibe Island |
| 官网 | https://vibeisland.app |
| 定价 | $19.99 一次性买断 / 1 台 Mac，+$10 每增加一台 |
| 开源 | 否（闭源），仅 auto-update 仓库公开 |
| 开发者 | Edward Luo（GitHub: edwluo，Twitter: @edwardluox） |
| 技术栈 | 原生 Swift 6（严格并发模式），SPM 构建 |
| 资源占用 | < 50 MB RAM，空闲 CPU ≈ 0，DMG ≈ 15 MB |
| 系统要求 | macOS 14+（Sonoma），Universal Binary（arm64 + x86_64）|
| 窗口架构 | 基于 boring.notch 架构的 NSPanel 非激活覆盖层 |
| 社区 | Discord / 微信群 / 飞书群 |
| 发布节奏 | 62 个版本 / 5 周（2026-03-03 ~ 04-05）|

---

## 2. 核心功能详解

### 2.1 会话监控面板

- 利用 MacBook 刘海区域展示 AI 编码会话
- 每张卡片：项目名称、用户消息预览、AI 回复预览、标签（Claude/VS Code/终端）、时长
- 顶栏：5h/7d 用量统计、剩余/已用百分比切换
- 空闲 >15min 的会话自动折叠为单行
- 无活跃会话时 notch 自动隐藏（可配置）

### 2.2 GUI 权限审批（杀手功能）

- notch 展开显示 Allow / Deny 按钮（Cmd+Y / Cmd+N）
- 丰富审批详情：Edit diff、Write 预览、Bash 命令描述、Read/WebFetch 预览、ExitPlanMode 4 选项
- 并行权限队列（多个请求排队）
- "Allow All" 批量审批 + "Yolo mode" 一键跳过
- 智能面板抑制：终端在前台时不自动展开
- 2 小时超时窗口

### 2.3 AskUserQuestion GUI

- Claude 提问直接出现在 notch
- 多选 / 自由文本回答

### 2.4 Plan Review

- 完整 Markdown 渲染（标题、代码块、列表）
- 直接 Approve 或提交反馈

### 2.5 终端跳转

- 点击会话精确跳转到对应终端 Tab/Pane
- 支持 13+ 终端 + tmux 分屏
- iTerm2 tmux -CC 跳转：1370ms → 200ms（AppleScript pane cache）

### 2.6 音效系统

- 8-bit 合成芯片音效（实时合成，非采样播放）
- 支持音频设备热切换

### 2.7 其他

- Session Switcher 键盘导航
- IDE 扩展自动安装（VS Code/Cursor/Windsurf）
- 全屏应用中鼠标移到顶部可唤出
- 多语言：EN / ZH-Hans / JA / KO

### 2.8 支持的 AI Agent（10+）

| Agent | 通信方式 |
|-------|---------|
| Claude Code | Hooks + Unix Socket |
| OpenAI Codex | JSONL 监听 + Notify Hook |
| Google Gemini CLI | Hooks |
| Cursor Agent | Hooks + VS Code 扩展 |
| OpenCode | SSE + REST |
| Factory Droid | Hooks |
| CodeBuddy CLI | Hooks |
| Qoder CLI | 自动配置 |
| CodePilot | 桌面应用会话追踪 |
| Copilot CLI | v1.0.16 新增 |

### 2.9 支持的终端（13+）

iTerm2（含 tmux -CC）、Ghostty 1.3+、Terminal.app、Warp、Alacritty、Kitty、VS Code / Cursor / Windsurf 集成终端、cmux（Socket JSON-RPC）、WezTerm、Kaku、Termius、Superset、Conductor、Zed、Hyper

---

## 3. Claude Code Hook 完整协议

### 3.1 通用输入字段（所有事件）

所有 hook 通过 stdin 接收 JSON：

```json
{
  "session_id": "abc123-uuid",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/user/my-project",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse"
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `session_id` | string | 会话 UUID |
| `transcript_path` | string | 对话 JSONL 文件绝对路径 |
| `cwd` | string | hook 触发时的工作目录 |
| `permission_mode` | string | `"default"` / `"plan"` / `"acceptEdits"` / `"auto"` / `"dontAsk"` / `"bypassPermissions"`（部分事件无此字段）|
| `hook_event_name` | string | 事件名称 |
| `agent_id` | string? | 子代理内部才有 |
| `agent_type` | string? | `--agent` 模式或子代理类型 |

### 3.2 各事件输入 Schema

#### SessionStart
```json
{
  "hook_event_name": "SessionStart",
  "source": "startup",        // matcher: "startup" | "resume" | "clear" | "compact"
  "model": "claude-sonnet-4-6",
  "agent_type": "optional"
}
```

#### SessionEnd
```json
{
  "hook_event_name": "SessionEnd",
  "reason": "clear"            // matcher: "clear" | "resume" | "logout" | "prompt_input_exit" | "bypass_permissions_disabled" | "other"
}
```

#### UserPromptSubmit
```json
{
  "hook_event_name": "UserPromptSubmit",
  "prompt": "Write a function to calculate factorial"
}
```

#### PreToolUse
```json
{
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",          // matcher 匹配字段
  "tool_input": { "command": "npm test" },
  "tool_use_id": "toolu_01abc"
}
```

#### PostToolUse
```json
{
  "hook_event_name": "PostToolUse",
  "tool_name": "Bash",
  "tool_input": { "command": "npm test" },
  "tool_response": "... tool output ...",
  "tool_use_id": "toolu_01abc"
}
```

#### PostToolUseFailure
```json
{
  "hook_event_name": "PostToolUseFailure",
  "tool_name": "Bash",
  "tool_input": { "command": "npm test" },
  "tool_use_id": "toolu_01abc",
  "error": "Command failed with exit code 1",
  "is_interrupt": false
}
```

#### PermissionRequest
```json
{
  "hook_event_name": "PermissionRequest",
  "tool_name": "Bash",
  "tool_input": { "command": "rm -rf node_modules" },
  "permission_suggestions": [
    {
      "type": "addRules",
      "rules": [{ "toolName": "Bash", "ruleContent": "rm -rf node_modules" }],
      "behavior": "allow",
      "destination": "localSettings"
    }
  ]
}
```

#### Stop
```json
{
  "hook_event_name": "Stop",
  "stop_hook_active": false,
  "last_assistant_message": "Here is the implementation..."
}
```

#### SubagentStart
```json
{
  "hook_event_name": "SubagentStart",
  "agent_id": "agent-uuid",
  "agent_type": "Explore"
}
```

#### SubagentStop
```json
{
  "hook_event_name": "SubagentStop",
  "stop_hook_active": false,
  "agent_id": "agent-uuid",
  "agent_transcript_path": "/path/to/transcript.jsonl",
  "agent_type": "Explore",
  "last_assistant_message": "..."
}
```

#### Notification
```json
{
  "hook_event_name": "Notification",
  "message": "Claude needs your input",
  "title": "Permission Required",
  "notification_type": "permission_prompt"   // matcher: "permission_prompt" | "idle_prompt" | "auth_success" | "elicitation_dialog"
}
```

#### PreCompact / PostCompact
```json
// PreCompact
{ "hook_event_name": "PreCompact", "trigger": "auto", "custom_instructions": "..." }
// PostCompact
{ "hook_event_name": "PostCompact", "trigger": "auto", "compact_summary": "Summary..." }
```

#### StopFailure
```json
{
  "hook_event_name": "StopFailure",
  "error": "rate_limit",      // matcher: "rate_limit" | "authentication_failed" | "billing_error" | "server_error" | "max_output_tokens" | "unknown"
  "error_details": {},
  "last_assistant_message": "..."
}
```
> 注意：StopFailure 的输出和退出码完全被忽略

#### Elicitation
```json
{
  "hook_event_name": "Elicitation",
  "mcp_server_name": "my-server",
  "message": "Please enter your API key",
  "elicitation_id": "elicit-uuid",
  "requested_schema": {}
}
```

#### ConfigChange
```json
{
  "hook_event_name": "ConfigChange",
  "source": "user_settings",   // matcher: "user_settings" | "project_settings" | "local_settings" | "policy_settings" | "skills"
  "file_path": "/Users/user/.claude/settings.json"
}
```

#### CwdChanged / FileChanged
```json
{ "hook_event_name": "CwdChanged", "old_cwd": "/old", "new_cwd": "/new" }
{ "hook_event_name": "FileChanged", "file_path": "/path/.envrc", "event": "change" }
```

#### WorktreeCreate / WorktreeRemove
```json
{ "hook_event_name": "WorktreeCreate", "name": "feature-branch" }
{ "hook_event_name": "WorktreeRemove", "worktree_path": "/path/to/worktree" }
```

#### InstructionsLoaded
```json
{
  "hook_event_name": "InstructionsLoaded",
  "file_path": "/project/CLAUDE.md",
  "memory_type": "Project",     // "User" | "Project" | "Local" | "Managed"
  "load_reason": "session_start", // matcher: "session_start" | "nested_traversal" | "path_glob_match" | "include" | "compact"
  "globs": ["src/**/*.ts"],
  "trigger_file_path": "...",
  "parent_file_path": "..."
}
```

### 3.3 Hook 输出 Schema（stdout JSON）

退出码 0 时，Claude Code 解析 stdout 中的 JSON：

```json
{
  "continue": true,              // false = 停止 Claude
  "stopReason": "Build failed",  // continue=false 时显示给用户
  "suppressOutput": false,       // 隐藏 verbose 模式中的 stdout
  "decision": "block",           // "approve" | "block"
  "reason": "Why blocked",      // block 时显示给 Claude
  "systemMessage": "Warning",   // 警告信息显示给用户
  "hookSpecificOutput": {}       // 事件特定输出（见下）
}
```

#### PreToolUse 专用输出
```json
{
  "hookEventName": "PreToolUse",
  "permissionDecision": "allow",      // "allow" | "deny" | "ask" | "defer"
  "permissionDecisionReason": "Auto-approved",
  "updatedInput": { "command": "npm run lint" },  // 可修改工具输入
  "additionalContext": "Extra context for Claude"
}
```
> 多个 hook 的优先级：deny > defer > ask > allow

#### PermissionRequest 专用输出
```json
{
  "hookEventName": "PermissionRequest",
  "decision": {
    "behavior": "allow",          // "allow" | "deny"
    "updatedInput": {},            // 可选：修改工具输入
    "updatedPermissions": [{       // 可选：持久化权限规则
      "type": "addRules",          // "addRules" | "replaceRules" | "removeRules" | "setMode"
      "rules": [{ "toolName": "Bash", "ruleContent": "npm *" }],
      "behavior": "allow",
      "destination": "session"     // "userSettings" | "projectSettings" | "localSettings" | "session" | "cliArg"
    }]
  }
}
```

Deny 时：
```json
{
  "hookEventName": "PermissionRequest",
  "decision": {
    "behavior": "deny",
    "message": "Reason for denial",
    "interrupt": true
  }
}
```

#### Elicitation 专用输出
```json
{
  "hookEventName": "Elicitation",
  "action": "accept",    // "accept" | "decline" | "cancel"
  "content": { "field1": "value1" }
}
```

### 3.4 退出码行为

| 退出码 | 含义 |
|--------|------|
| **0** | 成功，解析 stdout JSON |
| **2** | 阻断错误，stderr 发送给 Claude，stdout 被忽略 |
| **其他** | 非阻断错误，stderr 仅在 verbose 模式显示 |

Exit 2 只能阻断**未来动作**的事件（PreToolUse、PermissionRequest、UserPromptSubmit、Stop 等）。已完成事件（PostToolUse 等）的 exit 2 仅显示 stderr。

### 3.5 环境变量

| 变量 | 说明 |
|------|------|
| `CLAUDE_PROJECT_DIR` | 项目根目录 |
| `CLAUDE_PLUGIN_ROOT` | 插件安装目录 |
| `CLAUDE_PLUGIN_DATA` | 插件持久数据目录 |
| `CLAUDE_ENV_FILE` | 环境变量持久化文件（仅 SessionStart、CwdChanged、FileChanged）|
| `CLAUDE_CODE_REMOTE` | 远程环境时为 `"true"` |

### 3.6 异步 Hook

```json
{ "type": "command", "command": "run-tests.sh", "async": true, "timeout": 30 }
```
- 后台运行，不阻塞 Claude
- 不能返回 permissionDecision
- `asyncRewake: true` 时，exit 2 可唤醒模型

---

## 4. StatusLine JSON Schema

`statusLine.command` 通过 stdin 接收的完整 JSON（每次 UI 状态变化时触发，300ms 去抖，5s 超时）：

```json
{
  "session_id": "abc123-uuid",
  "transcript_path": "/Users/.../.claude/projects/.../transcript.jsonl",
  "cwd": "/Users/user/project",
  "session_name": "optional-session-name",
  "model": {
    "id": "claude-sonnet-4-6",
    "display_name": "Claude Sonnet 4.6"
  },
  "workspace": {
    "current_dir": "/Users/user/project",
    "project_dir": "/Users/user/project",
    "added_dirs": ["/Users/user/other-dir"]
  },
  "version": "2.1.90",
  "output_style": { "name": "streaming" },
  "cost": {
    "total_cost_usd": 0.0342,
    "total_duration_ms": 45230,
    "total_api_duration_ms": 12450,
    "total_lines_added": 156,
    "total_lines_removed": 23
  },
  "context_window": {
    "total_input_tokens": 15234,
    "total_output_tokens": 3456,
    "context_window_size": 200000,
    "current_usage": 18690,
    "used_percentage": 9.3,
    "remaining_percentage": 90.7
  },
  "exceeds_200k_tokens": false,
  "rate_limits": {
    "five_hour": {
      "used_percentage": 12.5,
      "resets_at": 1712345678
    },
    "seven_day": {
      "used_percentage": 3.2,
      "resets_at": 1712999999
    }
  },
  "vim": { "mode": "INSERT" },
  "agent": { "name": "security-reviewer" },
  "remote": { "session_id": "abc123" },
  "worktree": {
    "name": "feature-branch",
    "path": "/path/to/worktree",
    "branch": "feature-branch",
    "original_cwd": "/project",
    "original_branch": "main"
  }
}
```

**关键字段说明**：
- `rate_limits`：仅在有数据时出现（来自 HTTP 头 `anthropic-ratelimit-unified-5h-utilization`），约 23% 的请求中缺失
- `resets_at`：Unix 时间戳（秒）
- `vim`/`agent`/`remote`/`worktree`/`session_name`：可选字段，仅相关时出现
- Vibe Island 通过 statusline 脚本提取 `rate_limits` 缓存到 `/tmp/vibe-island-rl.json`，用 `mtime < 60s` 的最后已知好值做缓存

---

## 5. 权限审批双向通信机制

这是 Vibe Island 的**核心差异化功能**。完整流程：

### 5.1 通信流程

```
Claude Code ──[PermissionRequest hook]──> bridge binary
    ↓ (stdin JSON)
bridge binary ──[Unix Socket]──> Vibe Island.app
    ↓ (bridge 保持连接，阻塞等待)
Vibe Island UI ──[展开 notch，显示 Allow/Deny]
    ↓ (用户点击)
Vibe Island.app ──[Unix Socket 响应]──> bridge binary
    ↓ (写 JSON 到 stdout)
bridge binary ──[exit 0 + stdout JSON]──> Claude Code
    ↓
Claude Code 根据 decision 执行或拒绝
```

### 5.2 开源实现参考（Claude Island）

**Hook 脚本**（Python，打包在 app 内，复制到 `~/.claude/hooks/`）：

```python
# 简化版：claude-island-state.py
import socket, json, sys, os

def main():
    payload = json.loads(sys.stdin.read())
    event = payload.get("hook_event_name")
    
    # 构造发送给 app 的消息
    msg = {
        "session_id": payload.get("session_id"),
        "cwd": payload.get("cwd"),
        "event": event,
        "tool": payload.get("tool_name"),
        "tool_input": payload.get("tool_input"),
        "tool_use_id": payload.get("tool_use_id"),
        "pid": os.getppid(),
        "tty": get_tty()
    }
    
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect("/tmp/claude-island.sock")
    sock.sendall(json.dumps(msg).encode() + b"\n")
    
    if event == "PermissionRequest":
        # 阻塞等待 GUI 响应（最多 300 秒）
        sock.settimeout(300)
        response = json.loads(sock.recv(4096).decode())
        # 输出给 Claude Code
        if response["decision"] == "allow":
            output = {
                "hookSpecificOutput": {
                    "hookEventName": "PermissionRequest",
                    "decision": {"behavior": "allow"}
                }
            }
        else:
            output = {
                "hookSpecificOutput": {
                    "hookEventName": "PermissionRequest",
                    "decision": {"behavior": "deny", "message": response.get("message", "")}
                }
            }
        print(json.dumps(output))
    
    sock.close()

main()
```

**App 端 Socket 服务器**（Swift）：

```swift
// HookSocketServer.swift (Claude Island)
class HookSocketServer {
    let socketPath = "/tmp/claude-island.sock"
    var pendingPermissions: [String: Int32] = [:]  // toolUseId -> client fd
    
    func handleConnection(clientFd: Int32) {
        let data = readFromSocket(clientFd)
        let event = parseHookEvent(data)
        
        if event.isPermissionRequest {
            // 保存 fd，等待 GUI 响应
            pendingPermissions[event.toolUseId] = clientFd
            delegate?.hookReceived(event)  // 通知 UI 层
        } else {
            // 非权限事件，fire-and-forget
            delegate?.hookReceived(event)
            close(clientFd)
        }
    }
    
    func respondToPermission(toolUseId: String, decision: String) {
        guard let fd = pendingPermissions.removeValue(forKey: toolUseId) else { return }
        let response = """
        {"decision": "\(decision)"}
        """
        write(fd, response)
        close(fd)
    }
}
```

### 5.3 开源实现参考（my-code-island）

与 Claude Island 的关键差异：

| 方面 | Claude Island | my-code-island |
|------|-------------|----------------|
| Bridge | Python 脚本 | 编译的 Swift 二进制 |
| Socket 协议 | 原始 JSON + 换行符 | **长度前缀帧**（4 字节 big-endian UInt32 + JSON）|
| 阻塞机制 | Socket 保持打开 | `DispatchSemaphore` 阻塞 bridge 线程 |
| 额外功能 | - | 拦截 AskUserQuestion，展示交互式选项 UI |

**长度前缀帧协议**（my-code-island）：
```
[4 bytes: big-endian UInt32 长度][N bytes: UTF-8 JSON 载荷]
```

### 5.4 toolUseId 匹配技巧

Claude Island 的一个精妙设计：`PreToolUse` 包含 `tool_use_id`，但 `PermissionRequest` 不总是包含。解决方案：

```swift
// 从 PreToolUse 缓存 tool_use_id 到 FIFO 队列
// key = "sessionId:toolName:serializedInput"
var toolUseIdCache: [String: [String]] = [:]

func cacheToolUseId(event: HookEvent) {
    let key = "\(event.sessionId):\(event.toolName):\(event.toolInput)"
    toolUseIdCache[key, default: []].append(event.toolUseId)
}

// PermissionRequest 到达时，用相同 key 弹出匹配的 toolUseId
func matchToolUseId(event: HookEvent) -> String? {
    let key = "\(event.sessionId):\(event.toolName):\(event.toolInput)"
    return toolUseIdCache[key]?.removeFirst()
}
```

### 5.5 回退与异常处理

- 如果用户在终端（而非 GUI）中批准了权限，`PostToolUse` 事件到达后，取消对应的 pending socket
- 如果 Socket 连接断开，触发 `permissionSocketFailed` 事件清理 UI 状态
- 非权限事件到达时，如果会话处于 `waitingPermission` 状态，推断权限已在终端处理，清除过期请求

---

## 6. macOS Notch 区域 UI 渲染技术

### 6.1 窗口类型：NSPanel

**RECOMMENDATION**: 使用 `NSPanel`（不是 `NSWindow`），配合 `.borderless + .nonactivatingPanel` styleMask。

所有成功的 notch 应用（boring.notch 5k+ stars、Claude Island、my-code-island、DynamicNotchKit）都使用这个模式。

```swift
class NotchPanel: NSPanel {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask,
                  backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        
        // 核心配置
        self.isFloatingPanel = true           // 浮在普通窗口之上
        self.isOpaque = false                 // 透明背景
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovable = false
        self.level = .mainMenu + 3            // 27，在菜单栏之上
        self.appearance = NSAppearance(named: .darkAqua)  // 强制暗色
        self.collectionBehavior = [
            .fullScreenAuxiliary,             // 全屏时可用
            .stationary,                      // Space 切换时不跟随
            .canJoinAllSpaces,                // 所有桌面可见
            .ignoresCycle,                    // Cmd+Tab 中隐藏
        ]
    }
    
    override var canBecomeKey: Bool { false }  // 不获取焦点
    override var canBecomeMain: Bool { false }
}
```

**NSWindow.Level 层级参考**：
```
.normal       = 0
.floating     = 3
.mainMenu     = 24    ← boring.notch 用 +3 = 27
.statusBar    = 25    ← NotchDrop 用 +8 = 33
.screenSaver  = 101   ← DynamicNotchKit 用这个
```

**Vibe Island 确认使用**：boring.notch 架构的 NSPanel（v0.6.0 迁移）。

### 6.2 Notch 检测与定位

```swift
extension NSScreen {
    /// 检测物理 notch 是否存在
    var hasNotch: Bool {
        safeAreaInsets.top > 0 &&
        auxiliaryTopLeftArea != nil &&
        auxiliaryTopRightArea != nil
    }
    
    /// 计算 notch 精确尺寸（点）
    var notchSize: NSSize? {
        guard let leftArea = auxiliaryTopLeftArea,
              let rightArea = auxiliaryTopRightArea else { return nil }
        let notchWidth = frame.width - leftArea.width - rightArea.width + 4  // +4 对齐修正
        let notchHeight = safeAreaInsets.top
        return NSSize(width: notchWidth, height: notchHeight)
    }
    
    /// notch 在屏幕坐标中的 frame
    var notchFrame: NSRect? {
        guard let size = notchSize else { return nil }
        return NSRect(
            x: frame.midX - (size.width / 2),
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
    
    /// 非 notch 显示器的菜单栏高度
    var menubarHeight: CGFloat {
        frame.maxY - visibleFrame.maxY
    }
}
```

**关键 API**（macOS 12+）：
- `NSScreen.safeAreaInsets.top`：notch 高度（点）
- `NSScreen.auxiliaryTopLeftArea`：notch 左侧可用区域
- `NSScreen.auxiliaryTopRightArea`：notch 右侧可用区域

### 6.3 自定义 Notch 形状（圆角梯形）

```swift
struct NotchShape: Shape {
    var topCornerRadius: CGFloat    // 收起: 6pt, 展开: 19pt
    var bottomCornerRadius: CGFloat // 收起: 14pt, 展开: 24pt
    
    // 使圆角可动画
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set { topCornerRadius = newValue.first; bottomCornerRadius = newValue.second }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // 左上圆角（二次贝塞尔曲线）
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )
        // 左侧边
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius,
                                 y: rect.maxY - bottomCornerRadius))
        // 左下圆角
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )
        // 底边 + 右下 + 右侧 + 右上（对称）
        // ... 镜像处理
        return path
    }
}
```

用作 SwiftUI mask：
```swift
.mask {
    NotchShape(topCornerRadius: isExpanded ? 19 : 6,
               bottomCornerRadius: isExpanded ? 24 : 14)
}
```

### 6.4 窗口定位策略

**两种主流方案**：

**方案 A（Claude Island 方案）**：固定大窗口 + SwiftUI 内部动画
- 窗口始终 750pt 高、全屏宽
- SwiftUI 内容通过 `.frame()` 和 `.mask()` 控制可见区域
- 展开/收起不需要改变窗口大小
- ✅ 更流畅（无窗口 resize 闪烁）

```swift
let size = NSSize(width: screen.frame.width, height: 750)
let origin = NSPoint(x: screen.frame.origin.x,
                     y: screen.frame.maxY - size.height)
panel.setFrame(NSRect(origin: origin, size: size), display: false)
```

**方案 B（my-code-island 方案）**：窗口跟随动画 resize
- 收起时：窗口精确覆盖 notch
- 展开时：窗口放大到 380x420
- 用 `NSAnimationContext.runAnimationGroup` 动画

```swift
NSAnimationContext.runAnimationGroup { ctx in
    ctx.duration = 0.3
    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    panel.animator().setFrame(expandedFrame, display: true)
}
```

**RECOMMENDATION**: 方案 A（固定大窗口），动画更流畅。

### 6.5 鼠标追踪与展开/收起

**全局事件监听**（最可靠）：

```swift
class EventMonitor {
    private var globalMonitor: AnyObject?
    
    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { _ in
            let pos = NSEvent.mouseLocation
            let inNotch = self.notchRect.insetBy(dx: -10, dy: -5).contains(pos)
            
            if inNotch && !self.isExpanded {
                // 停留检测：0.4s 后展开
                self.startDwellTimer()
            } else if !inNotch && self.isExpanded {
                // 延迟收起（防抖）
                self.scheduleCollapse(delay: 0.15)
            }
        }
    }
}
```

**Claude Island 的做法**：
- 全局 `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)`
- Combine `CurrentValueSubject` 发布鼠标位置，50ms 节流
- 1 秒 hover 后自动展开
- 点击面板外部收起 + 将点击事件重新投递（`CGEvent.post`）

**boring.notch 的做法**：
- SwiftUI `.onHover` + 可配置 `minimumHoverDuration`
- 可取消的 `Task` 做去抖

### 6.6 动画配置

```swift
// 展开：弹性弹跳
withAnimation(.bouncy(duration: 0.4)) { state = .expanded }

// 收起：平滑
withAnimation(.smooth(duration: 0.4)) { state = .hidden }

// 或用 interactiveSpring
withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) { ... }
```

**消除首帧闪烁的技巧**：先启动 SwiftUI 动画，再显示窗口：
```swift
withAnimation(.bouncy(duration: 0.4)) { self.state = .expanded }
// 动画已在进行中，现在显示窗口
showWindow()  // alphaValue 0 → 1 淡入
```

### 6.7 点击穿透

```swift
// NSHostingView 子类，仅在活跃区域内接受点击
class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var activeRect: NSRect = .zero
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // 点在活跃区域内：正常处理
        if activeRect.contains(convert(point, from: nil)) {
            return super.hitTest(point)
        }
        // 点在活跃区域外：穿透到下层（菜单栏等）
        return nil
    }
}
```

### 6.8 多显示器支持

```swift
// 每个屏幕创建独立的窗口和 ViewModel
var windows: [String: NSWindow] = [:]

for screen in NSScreen.screens where screen.hasNotch {
    guard let uuid = screen.displayUUID else { continue }
    let vm = NotchViewModel(screenUUID: uuid)
    let window = createNotchPanel(for: screen, with: vm)
    windows[uuid] = window
}

// 监听屏幕配置变化
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification, ...)
```

> **Vibe Island 已知限制**：`NotchViewModel` 是单例，`PanelController` 管理单个窗口，所以暂不支持多显示器。

### 6.9 可选：DynamicNotchKit 作为依赖

如果想快速实现，可以直接用 DynamicNotchKit（384+ stars）：

```swift
// Package.swift
.package(url: "https://github.com/MrKai77/DynamicNotchKit", from: "3.0.0")

// 使用
let notch = DynamicNotch(hoverBehavior: .all, style: .auto) {
    AgentMonitorView()     // 展开内容
} compactLeading: {
    Image(systemName: "terminal")
} compactTrailing: {
    Text("3 agents")
}
await notch.expand()
```

---

## 7. 终端检测与跳转实现

### 7.1 检测流程

```
Claude Code PID
    ↓ 向上遍历进程树
    ↓ ps -eo pid,ppid,tty,comm
    ↓ 匹配已知终端 Bundle ID
    ↓ 获取 TTY
    ↓ 检测 tmux: tmux list-panes -a -F "#{pane_tty} #{pane_id}"
```

**进程树构建**（Claude Island）：
```bash
ps -eo pid,ppid,tty,comm
```
从 Claude PID 向上遍历 ppid 链，直到找到已知终端应用。

**sysctl 方式**（my-code-island，更高效）：
```swift
// 用 sysctl KERN_PROC_PID 获取 ppid，不需要 spawn ps
var info = kinfo_proc()
var size = MemoryLayout<kinfo_proc>.stride
var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
sysctl(&mib, 4, &info, &size, nil, 0)
let ppid = info.kp_eproc.e_ppid
```

### 7.2 已知终端注册表

```swift
enum TerminalApp: String {
    case terminal = "com.apple.Terminal"
    case iterm2 = "com.googlecode.iterm2"
    case ghostty = "com.mitchellh.ghostty"
    case alacritty = "org.alacritty"
    case kitty = "net.kovidgoyal.kitty"
    case warp = "dev.warp.Warp-Stable"
    case wezterm = "com.github.wez.wezterm"
    case vscode = "com.microsoft.VSCode"
    case cursor = "com.todesktop.230313mzl4w4u92"
    case windsurf = "..."
    case zed = "dev.zed.Zed"
    case hyper = "co.zeit.hyper"
    // ...
}
```

### 7.3 tmux 支持

```bash
# 列出所有 tmux pane 及其 PID
tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index} #{pane_pid}"

# 跳转到指定 pane
tmux select-window -t "session:window"
tmux select-pane -t "session:window.pane"
```

### 7.4 终端跳转实现（my-code-island 的 TerminalJumper）

优先级策略：
1. tmux 会话：`tmux select-window` + `tmux select-pane`
2. iTerm2：AppleScript `write text` by TTY
3. 通用终端：`NSRunningApplication.activate()` + AppleScript
4. 最后手段：剪贴板粘贴（`Cmd+V` via System Events）

```swift
class TerminalJumper {
    func jumpToSession(_ session: TrackedSession) {
        if let tmuxPaneId = session.tmuxPaneId {
            // tmux: 精确 pane 跳转
            shell("tmux select-window -t \(tmuxPaneId)")
            shell("tmux select-pane -t \(tmuxPaneId)")
        }
        // 激活终端应用
        if let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: session.terminalBundleId).first {
            app.activate()
        }
    }
}
```

### 7.5 Vibe Island 的终端跳转优化历程

| 版本 | 优化 |
|------|------|
| v0.6.4 | Bundle ID 自动检测 |
| v0.8.0 | Terminal.app 精确 Tab 跳转 |
| v0.8.1 | Ghostty Tab 精确跳转（点击通知）|
| v0.8.2 | 预激活窗口加速跳转 |
| v0.9.0 | iTerm2 tmux -CC: 1370ms → 200ms（AppleScript pane cache）|
| v0.9.0 | Ghostty AX-based tab cache |
| v0.9.1 | Warp 精确 Tab + 分屏跳转 |
| v0.9.6 | Ghostty 1.3+ AppleScript 跳转（无视觉闪烁）|
| v0.9.6 | UUID caching（重命名不影响跳转）|
| v1.0.0 | cmux: Socket JSON-RPC 跳转 |
| v1.0.19 | WezTerm + Kaku 精确跳转 |

---

## 8. 开源竞品架构对比

### 8.1 Claude Island vs my-code-island

| 方面 | Claude Island | my-code-island |
|------|-------------|----------------|
| **Bridge** | Python 脚本（打包 .py）| 编译 Swift 二进制 |
| **Socket 协议** | 原始 JSON + 换行符 | 长度前缀帧（4 byte header + JSON）|
| **Socket 路径** | `/tmp/claude-island.sock` | `/tmp/code-island.sock` |
| **窗口策略** | 固定 750pt 全宽，SwiftUI 内部动画 | 窗口实际 resize |
| **窗口层级** | `mainMenu + 3` | `CGShieldingWindowLevel()` |
| **鼠标穿透** | toggle `ignoresMouseEvents` + 自定义 hitTest | 始终接受鼠标 |
| **状态管理** | Swift `actor` + 事件驱动状态机 | `@Observable` class on MainActor |
| **会话发现** | 仅 Hook 事件 | Hook 事件 + 文件系统轮询（5s）|
| **JSONL 解析** | 增量解析聊天历史 | 无（仅 Hook）|
| **聊天视图** | 有（完整历史 + 工具结果）| 无（仅状态卡片）|
| **权限阻塞** | Socket 保持打开等待 Python 脚本 | Semaphore 阻塞 bridge 线程 |
| **AskUserQuestion** | 不拦截 | 拦截 + 交互式选项 UI |
| **Codex 支持** | 无 | 有（`--source codex`）|
| **tmux 检测** | `tmux list-panes` + 进程树遍历 | TTY 匹配 |
| **窗口管理器** | yabai 集成 | 直接 `NSRunningApplication.activate()` |
| **分析** | Mixpanel | 无 |
| **自动更新** | Sparkle | 无 |

### 8.2 Claude Island 的会话状态机

```swift
enum SessionPhase {
    case idle
    case processing
    case waitingForInput
    case waitingForApproval(PermissionContext)
    case compacting
    case ended  // 终态
}
```

状态转换有验证（如 `ended` 是终态不可回退）。

### 8.3 my-code-island 的权限模式

```swift
enum PermissionMode {
    case observe      // 仅观察，不拦截
    case alwaysAllow  // 自动批准所有
    case manual       // 显示 UI 等待用户决定
}
```

---

## 9. notchOS 现有架构 vs 差距分析

### 9.1 当前架构

```
notchOS 架构（3 层）：

1. Swift 原生层（Sources/NotchConsole/main.swift）
   └── NSPanel + WKWebView + 鼠标监听 + 音效 + JS Bridge

2. Python FastAPI 后端（backend/）→ 127.0.0.1:23456
   ├── POST /hook     ← 接收 Hook 事件
   ├── GET /api/state ← 返回会话状态
   ├── WS /ws         ← WebSocket 实时推送
   └── /ui            ← 静态文件服务

3. Web UI（ui/）→ HTML + CSS + JS（WKWebView 中渲染）
   ├── 收起模式：状态点 + 文字 + 工具名（对齐 notch）
   └── 展开模式：会话卡片 Dashboard
```

### 9.2 已有功能

- ✅ NSPanel overlay（不偷焦点）
- ✅ Notch 几何检测 + 非 notch 回退
- ✅ 双区域 hover 检测（0.4s 停留阈值）
- ✅ Hook 脚本（15 种事件，零依赖 Python，fire-and-forget）
- ✅ 状态管理（8 种显示状态 + TTL 自动降级）
- ✅ Aurora 极光动画（彩虹渐变光带 + 外发光）
- ✅ 状态动画（pulse/breathe/green-alert/notification-freeze）
- ✅ Confetti 完成庆祝动画
- ✅ 音效通知（NSSound，3s 去抖）
- ✅ WebSocket + 轮询回退（5s 轮询，3s 重连）
- ✅ 多会话支持（pill 显示主导状态，dashboard 显示个别卡片）
- ✅ 构建/打包脚本（swift build + .app + ad-hoc codesign）

### 9.3 差距（对比 Vibe Island）

| 功能 | Vibe Island | notchOS |
|------|-------------|---------|
| **GUI 权限审批** | ✅ 双向通信 | ❌ 仅 fire-and-forget |
| **AskUserQuestion GUI** | ✅ 交互式回答 | ❌ |
| **Plan Review** | ✅ Markdown 渲染 | ❌ |
| **终端跳转** | ✅ 13+ 终端精确跳转 | ❌ 仅展示 |
| **Token/用量追踪** | ✅ 5h/7d 用量显示 | ❌ |
| **多 Agent 支持** | ✅ 10+ Agent | ❌ 仅 Claude Code |
| **多显示器** | ⚠️ 受限 | ❌ |
| **键盘快捷键** | ✅ Carbon Hot Key | ❌ |
| **设置 UI** | ✅ | ❌ |
| **自动启动** | ✅ LaunchAgent | ❌ |
| **菜单栏图标** | ✅ | ❌ |
| **会话历史** | ✅ JSONL 增量解析 | ❌ |
| **测试覆盖** | ✅ | ❌ |

### 9.4 架构差异分析

| 方面 | Vibe Island | notchOS | 评价 |
|------|-------------|---------|------|
| 通信 | 编译 Swift bridge + Unix Socket | Python hook → HTTP POST | notchOS 的 HTTP 方案无法实现双向阻塞通信（权限审批所需） |
| UI | 原生 SwiftUI | WKWebView + HTML/CSS/JS | WKWebView 方案灵活但 latency 更高，且无法像 SwiftUI 那样用 `.mask(NotchShape())` |
| 状态管理 | Swift actor | Python in-memory dict | Python 方案增加了进程间通信复杂度 |
| 构建 | SPM + Sparkle 自动更新 | 手动 `swift build` + ad-hoc sign | 缺少分发和更新机制 |

---

## 10. 性能优化编年史（Vibe Island）

| 版本 | 优化 |
|------|------|
| v0.5.1 | JSONL 解析性能优化；hover 冷却窗口 |
| v0.5.4 | 内存优化 |
| v0.5.5 | Carbon Hot Key API（不偷焦点的快捷键）|
| v0.6.0 | 迁移到 boring.notch 窗口架构 |
| v0.6.1 | 迁移到 SPM 构建（更好的 crash log 符号化）|
| v0.6.6 | Swift 6 严格并发模式 |
| v0.7.0 | 自适应轮询：300ms（活跃）/ 1-3s（空闲）|
| v0.7.3 | 减少 hook 中的系统调用 |
| v0.7.6 | 第三方 hook 保护（不再意外删除其他工具的 hook）|
| v0.7.7 | Hook 响应速度 10x 提升 |
| v0.8.0 | toolUseId 精确匹配实现即时审批检测 |
| v0.8.2 | 预激活窗口加速终端跳转 |
| v0.9.0 | iTerm2 tmux -CC: 1370ms → 200ms |
| v0.9.7 | 修复 AX 观察者导致的 CPU 占用 |
| v0.9.8 | 修复全屏检测在主线程导致的卡顿 |
| v1.0.3 | Hook 自动恢复（被其他工具覆盖后）|
| v1.0.4 | 智能 hook 配置（适配不同 Claude Code 版本）|
| v1.0.7 | 减少内存占用和后台 CPU 活动 |
| v1.0.19 | Codex 监控开关（不用时零开销）|

---

## 11. 竞品对比总表

| 产品 | 类型 | 开源 | 价格 | Stars | Agent 数 | 权限审批 | 终端跳转 | 独特功能 | 技术栈 |
|------|------|------|------|-------|----------|----------|----------|----------|--------|
| **Vibe Island** | Notch | ❌ | $19.99 | - | 10+ | ✅ | ✅ 13+ | Plan Review / 8-bit 音效 | Swift 原生 |
| **CodeIsland** | Notch | ✅ CC-BY-NC | 免费 | 172 | 1 | ✅ diff 预览 | ✅ cmux/iTerm/Ghostty | iPhone Code Light / Buddy 像素猫 / Quick Reply | Swift + SwiftUI |
| **Claude Island** | Notch | ✅ | 免费 | 1,866 | 1 | ✅ | ✅ | 零配置自动安装 hooks / 聊天历史 | Swift + Python |
| **my-code-island** | Notch | ✅ | 免费 | - | 2 | ✅ | ✅ | Codex 支持 / AskUser 交互 | Swift |
| **boring.notch** | Notch | ✅ GPL-3 | 免费 | 8,000+ | 0 | - | - | 音乐可视化 / 文件 Shelf / HUD 替换 / SkyLight 录屏隐藏 | Swift + SwiftUI |
| **Atoll** | Notch | ✅ GPL-3 | 免费 | 1,700 | 0 | - | - | 手势控制 / C++ MediaRemote / SMC 硬件 / 锁屏 Widget | Swift |
| **mew-notch** | Notch | ✅ | 免费 | 489 | 0 | - | - | Lottie 动画 / 系统 HUD 替换 / Sparkle 自动更新 | Swift + SwiftUI + ObjC |
| **SessionWatcher** | Menu bar | ❌ | $2.99 | - | 2 | ❌ | ❌ | - | - |
| **TokenEater** | Menu bar | ✅ | 免费 | - | 1 | ❌ | ❌ | - | - |
| **DynamicNotchKit** | SDK | ✅ | 免费 | 384 | 0 | - | - | 通知 API 封装 | Swift Package |
| **notchOS** | Notch | 自研 | - | - | 1 | ❌ | ❌ | WebSocket 实时 / 模块化内容系统 / 设置窗口 | Swift + Python + HTML |

---

## 12. 参考链接

### 产品
- Vibe Island 官网：https://vibeisland.app
- Vibe Island Claude Code 页：https://vibeisland.app/claude-code/
- Vibe Island Updates：https://github.com/edwluo/vibe-island-updates

### 开源竞品（AI Agent 监控，有完整源码）
- CodeIsland（172 stars）：https://github.com/xmqywx/CodeIsland — VibeIsland 开源替代，功能最全
- Claude Island（1,866 stars）：https://github.com/farouqaldori/claude-island
- my-code-island：https://github.com/obrr-hhx/my-code-island

### macOS Notch UI 参考项目
- boring.notch（8,000+ stars）：https://github.com/TheBoredTeam/boring.notch — VibeIsland 架构基础
- Atoll（1,700 stars）：https://github.com/Ebullioscopic/Atoll — 手势交互 + C++ MediaRemote
- mew-notch（489 stars）：https://github.com/monuk7735/mew-notch — 系统 HUD 替换
- NotchDrop（2k+ stars）：https://github.com/Lakr233/NotchDrop
- DynamicNotchKit（384+ stars）：https://github.com/MrKai77/DynamicNotchKit

### 文章 / 教程
- CodeIsland 开发博文：https://dev.to/krisying/i-turned-my-macbooks-notch-into-a-control-center-for-ai-coding-agents-2o57

---

## 13. 设置页面完整功能清单（截图分析 2026-04-05）

> 来源：Vibe Island 设置页面截图（通用、显示、声音、快捷键、实验室、通行证、关于共 7 个 Tab）

### 13.1 通用 (General)

**行为设置：**

| 设置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| 全屏时隐藏 | Toggle | 开 | 全屏应用中不显示 notch overlay |
| 无活跃会话时自动隐藏 | Toggle | 开 | 没有 session 时 notch 消失 |
| 智能抑制 | Toggle | 开 | Agent 所在终端标签页在前台时不自动展开面板 |
| 鼠标离开时自动收起 | Toggle | 开 | hover 离开面板区域后自动收起 |
| 显示用量限额 | Toggle | 开 | 在刘海面板顶部显示订阅用量限额 |
| 显示数值 | Dropdown | 已用量 | 已用量 / 剩余量切换 |

**CLI Hooks 管理：**
- Claude Code / Codex / Cursor Agent 各有独立开关（✅ 已激活 + Toggle）
- "添加 Claude Code 分支..." 按钮（支持多个 Claude Code 实例）
- 启动时自动配置 Hooks，可通过开关控制各 CLI 的自动配置

**IDE 扩展：**
- VS Code / Cursor 一键安装/卸载
- 安装扩展以精确跳转到 IDE 中的终端标签页

### 13.2 显示 (Display)

**刘海模式（Pill 样式）：**

| 模式 | 说明 |
|------|------|
| 简洁 | 仅绿色点 + 数字，给菜单栏图标让路 |
| 详细 | 绿色点 + 进度条 + 数字 + "ses" 标签，会话标题和状态一目了然 |

**尺寸控制：**

| 设置项 | 类型 | 默认值 | 范围 |
|--------|------|--------|------|
| 内容字体大小 | Dropdown | 11pt | 可选多档 |
| 完成卡片高度 | Slider | 90pt | 有最小/最大限制 |
| 最大面板高度 | Slider | 560pt | 有最小/最大限制 |

**Agents 活动详情：**
- Toggle 开关：显示代理活动详情
- 开启后面板内展示 **Subagent 树**：
  - 树形结构：`Subagents (2)` 标题
  - 每个 subagent 显示：蓝/绿点 + 类型描述（如 `Explore (Search API endpoints)`）+ 耗时（`8s`）或 `Done`
  - 子级显示当前工具调用（如 `└ Grep: handleRequest`）

**面板内容丰富度（从预览图观察）：**
- Edit diff 预览：红绿行（`- const token = getToken()` / `+ const token = refreshToken()`）
- 用户 prompt 显示：`You: Fix the login bug`
- AI 回复摘要：完整文本预览
- 状态标签：`Done`

### 13.3 快捷键 (Shortcuts)

**修饰键：** Control（可切换为其他修饰键）

**全局快捷键：**

| 快捷键 | 功能 | 说明 |
|--------|------|------|
| ^G | 切换面板 | 随处呼出，↑↓ 导航，Enter 跳转 |

**面板快捷键：**

| 快捷键 | 功能 |
|--------|------|
| ^Y | 批准（Approve） |
| ^N | 拒绝（Deny） |
| ^A | 始终允许（Always Allow） |
| ^B | 自动批准权限（Auto-approve permissions） |
| ^T | 跳转到终端 |

### 13.4 其他 Tab（截图未完整展示）

- **声音**：音效选择和音量控制（推测）
- **实验室**：实验性功能开关
- **通行证**：License 管理
- **关于**：版本信息

---

## 14. notchOS 可用性评估 + 优先级建议

> 基于设置页分析，结合 notchOS 当前架构（Swift/AppKit + Python 后端 + WKWebView + fire-and-forget hook）

### Tier 1：现有架构直接支持，投入产出比最高

| 功能 | 实现难度 | 原因 |
|------|----------|------|
| **简洁/详细双模式** | 低 | 纯 CSS/JS 变更，pill 区域两种渲染模式 |
| **最大面板高度可调** | 低 | Config.swift 改为运行时变量 + JS 传参给 Swift |
| **全屏时隐藏** | 低 | NSPanel `collectionBehavior` 移除 `.fullScreenAuxiliary` 即可 |
| **无活跃时自动隐藏** | 低 | JS 检测 sessions=0 → 通知 Swift 隐藏面板 |
| **内容字体大小可调** | 低 | CSS `--font-size` 变量 |

### Tier 2：需要额外数据，但架构可支持

| 功能 | 实现难度 | 原因 |
|------|----------|------|
| **Subagent 树** | 中 | hook.py 已捕获 SubagentStart/Stop + agent_type，需增加父子关系追踪和 UI 树形渲染 |
| **智能抑制** | 中 | Swift 检测 `NSWorkspace.shared.frontmostApplication` 是否为终端 app，与当前 session 关联 |
| **面板内容丰富化（diff/prompt/回复）** | 中 | hook.py 已接收 tool_input/tool_response，需传给前端渲染，数据量较大 |

### Tier 3：需要架构扩展或外部依赖

| 功能 | 实现难度 | 原因 |
|------|----------|------|
| **全局快捷键 (^G)** | 中-高 | 需要 Swift Carbon Hot Key API（不偷焦点），与现有 hover 检测并行 |
| **用量限额显示** | 中 | 需找到 Claude 用量数据源（API 或本地文件），定时拉取 |
| **CLI Hooks 管理 UI** | 高 | 需读写 `~/.claude/settings.json`，设计设置页面 |
| **权限审批快捷键 (^Y/^N)** | 高 | 需要双向通信（hook.py 阻塞等待用户决定），当前 fire-and-forget 架构不支持 |
| **IDE 扩展管理** | 高 | 需检测 VS Code/Cursor 安装路径 + 扩展安装 API |

### RECOMMENDATION

**先做 Tier 1 全部 + Tier 2 的 Subagent 树**。理由：

1. Tier 1 五项加起来工作量不大，但能让 notchOS 从"能用"变成"好用"
2. Subagent 树是**灵动岛功能的第一个真正内容模块** — 正好验证刚搭好的 content_modules 架构
3. 智能抑制虽然体验很好，但需要终端检测逻辑，可以放到 Subagent 树之后

暂时不做 Tier 3。权限审批需要改 hook 通信架构（fire-and-forget → 双向阻塞），这是一个独立的大工程。

---

### 技术文档
- Claude Code Hooks 文档：https://code.claude.com/docs/en/hooks
- NSPanel 文档：https://developer.apple.com/documentation/appkit/nspanel
- NSScreen.auxiliaryTopLeftArea：https://developer.apple.com/documentation/appkit/nsscreen/3882915-auxiliarytopleftarea
- NSWindow.Level 层级：https://jameshfisher.com/2020/08/03/what-is-the-order-of-nswindow-levels/
- Cindori 浮动面板教程：https://cindori.com/developer/floating-panel

---

## 15. 开源竞品深度调研（2026-04-09 补充）

> 来源：GitHub 源码分析 + DEV.to 技术博文 + Web 搜索
> 目的：找到 VibeIsland 的开源替代方案，识别 notchOS 可学习的功能和架构

### 15.1 CodeIsland — VibeIsland 的最完整开源替代

| 项目 | 内容 |
|------|------|
| GitHub | https://github.com/xmqywx/CodeIsland |
| Stars | 172 ⭐ / 27 forks / 202 commits |
| 许可证 | CC BY-NC 4.0（非商用） |
| 技术栈 | Swift + SwiftUI，~70 个 Swift 文件，Xcode 工程 |
| 系统要求 | macOS 15.0+，Universal Binary |
| 通信方式 | Python hook → Unix Socket (`/tmp/codeisland.sock`) + JSONL 监控 |
| 最后更新 | 2026-04-09（积极维护中） |

**核心功能：**

| 功能 | 说明 |
|------|------|
| 会话监控 | 实时显示所有 Claude Code 会话，色码标记（工作中=青、待批准=黄、完成=绿） |
| 权限审批 GUI | 直接在 notch 里预览代码 diff（绿/红高亮）并一键 Allow/Deny |
| 5h/7d 用量统计 | 直接读 Anthropic OAuth API + macOS Keychain，零配置 |
| 终端跳转 | 多层回退策略：cmux > Ghostty > iTerm2 > Terminal.app，AppleScript 精确路由 |
| Buddy 像素猫 | 18 种生物 + 5 维统计 + ASCII 精灵 + 稀有度评级，精确复现 Claude Code 的 hash 算法 |
| Quick Reply | Claude 的多选问题在 notch 显示为可点击按钮，通过 `cmux send` 回答 |
| Subagent 追踪 | 子 agent 实时显示 ⚡ 徽章 + 可折叠详情 |
| 智能通知抑制 | 检测当前终端前台状态，已可见的 session 不弹通知 |
| iPhone Code Light | 双向桥接（Mac ↔ 云 ↔ iPhone），远程看状态 + 发斜杠命令 + 远程启动 session |

**终端支持矩阵：**

| 终端 | 检测 | 跳转 | Quick Reply | 智能抑制粒度 |
|------|------|------|-------------|-------------|
| cmux | 自动 | Workspace 级 | ✅ | Workspace 级 |
| iTerm2 | 自动 | AppleScript | ✅ | Session 级 |
| Ghostty | 自动 | AppleScript | — | Window 级 |
| Terminal.app | 自动 | Activate | ✅ | Tab 级 |

**iPhone Code Light 协议细节：**
- 6 字符永久配对码（不轮转），支持多 iPhone / 多 Mac
- 终端路由：`ps -Ax` 进程检查 + 环境变量解析（`CMUX_WORKSPACE_ID`）
- 60 秒 dedup ring 防止 echo loop
- 支持 `/model`、`/cost`、`/usage`、`/clear` 等斜杠命令远程执行
- 图片通过 clipboard injection 附加
- 零知识中继架构，可自部署

**架构洞察（对 notchOS 的借鉴）：**

1. **Unix Socket 替代 HTTP**：hook 直接写 socket，无需中间 HTTP 服务器，延迟更低、架构更简
2. **多层终端回退**：不做单一适配，按优先级级联检测
3. **数据源分离**：会话状态（hooks）、Buddy 属性（`~/.claude.json`）、iPhone 消息（device code）各走独立通道，而非混合在一套 WebSocket
4. **Bun 中间层**：执行 `buddy-bones.js` 精确复现 Claude 的 `Bun.hash + Mulberry32` 算法
5. **Keychain 集成**：直接读 macOS Keychain 获取 OAuth token，用户无需手动配置

---

### 15.2 Claude Island — 零配置体验最好

| 项目 | 内容 |
|------|------|
| GitHub | https://github.com/farouqaldori/claude-island |
| Stars | 1,866 ⭐ / 263 forks |
| 技术栈 | 纯 Swift (95.7%)，Xcode 工程 |
| 系统要求 | macOS 15.6+ |
| 通信方式 | 自动安装 hooks → Unix Socket (`/tmp/claude-island.sock`) |
| 代码体量 | 817 KB |

**vs 8.1 节已有分析的补充：**

- **零配置**：首次启动自动在 `~/.claude/hooks/` 安装 hook 脚本，用户无需手动编辑 `settings.json`
- **状态机严格性**：`SessionPhase` 枚举有验证（`ended` 是终态不可回退），比简单 dict 更安全
- **多显示器**：检测当前焦点窗口位于哪个屏幕
- **聊天历史**：增量解析 JSONL transcript 文件，在 notch 展开区显示完整对话
- **窗口策略**：固定 750pt 全宽，内部 SwiftUI 动画（不做窗口 resize）
- **窗口层级**：`mainMenu + 3`（vs notchOS 的 `.statusBar`）

---

### 15.3 boring.notch — VibeIsland 的架构基础

| 项目 | 内容 |
|------|------|
| GitHub | https://github.com/TheBoredTeam/boring.notch |
| Stars | 8,000+ ⭐ / 593 forks / 1,195 commits / 50+ 贡献者 |
| 许可证 | GPL-3.0 |
| 技术栈 | Swift (98.2%) + SwiftUI + AppKit，Xcode 16+ |
| 系统要求 | macOS 14 Sonoma+，Universal Binary |

**核心功能**：音乐播放器 + 实时音频可视化、文件 Shelf（拖放 + AirDrop）、系统 HUD 替换（音量/亮度/键盘背光）、日历提醒集成、电池显示、屏幕镜像

**架构亮点：**

| 模块 | 说明 |
|------|------|
| `BoringNotchWindow` | NSPanel 子类：`isFloatingPanel=true`, `isOpaque=false`, `backgroundColor=.clear`, `level=.mainMenu+3`, `canBecomeKey/Main=false` |
| `BoringNotchSkyLightWindow` | 使用 SkyLight 私有框架，窗口在**屏幕录制/截图时自动隐藏** |
| `NotchShape` | 自定义 SwiftUI Shape 绘制 notch 轮廓，圆角参数可动画化过渡 |
| `MediaKeyInterceptor` | EventTap 拦截系统媒体键，不被其他 app 抢走 |
| `DragDetector` | NSEvent 全局监听 + pasteboard 变化检测，实现文件拖入 notch |
| `XPC Helper` | 敏感操作（辅助功能权限）隔离到独立进程 |
| `sneakPeek` | 通知视图，2 秒自动消退 |

**代码结构（17 个模块）**：
- 8 个核心管理器：MusicManager (739 行)、VolumeManager、BrightnessManager、CalendarManager 等
- 3 个观察器：MediaKeyInterceptor、DragDetector、FullscreenMediaDetection
- 多个媒体控制器：Spotify、Apple Music、Now Playing、YouTube Music
- IOKit 框架监控电池状态（基于 CFRunLoopSource）
- URLCache 配置 50MB 内存缓存

**对 notchOS 的借鉴价值**：
1. **SkyLight 录屏隐藏**：录屏/截图时自动隐藏 notch overlay，避免干扰
2. **DragDetector 全局事件监听**：可用于 WKWebView 内容拖拽
3. **XPC 进程隔离**：敏感权限操作分离到独立进程
4. **NotchShape 动画化圆角**：比 CSS border-radius 更精确匹配物理 notch

---

### 15.4 Atoll — 手势交互 + 深度硬件集成

| 项目 | 内容 |
|------|------|
| GitHub | https://github.com/Ebullioscopic/Atoll |
| Stars | 1,700 ⭐ |
| 许可证 | GPL-3.0 |
| 技术栈 | 纯 Swift (99.5%) |

**核心功能**：Apple Music/Spotify 控制、Focus 模式、屏幕录制、隐私指示器、电池/网络/内存监控、计时器、剪贴板历史、颜色选择器

**架构亮点：**
- **手势系统**：双指滑动控制展开/收起，水平手势切换面板内容（vs hover 更加 intentional）
- **C++ 桥接**：`MediaRemoteAdapter` 自定义 C++ 框架访问 MediaRemote 私有 API
- **SMC 硬件访问**：直接读取 CPU 温度/风扇转速
- **IOReport 频率采样**：精确硬件监控
- **锁屏 Widget**：天气、计时器、蓝牙设备
- **模块化**：MediaControlSystem / SystemMonitoring / LockScreenWidgets / GestureRecognition 分层

**对 notchOS 的借鉴价值**：
- 手势交互模式：如果用户觉得 hover 太容易误触，可以考虑双指滑动作为替代方案
- 多源数据聚合的 Widget 设计：适用于 notchOS 未来扩展多种内容模块

---

### 15.5 mew-notch — 轻量系统 HUD 替代

| 项目 | 内容 |
|------|------|
| GitHub | https://github.com/monuk7735/mew-notch |
| Stars | 489 ⭐ |
| 技术栈 | Swift (87.5%) + SwiftUI + Objective-C (9.5%) |

**核心功能**：将 macOS 的音量、亮度等系统 HUD 搬到 notch 区域显示

**架构亮点：**
- **Lottie 动画**：比纯 CSS 动画更流畅的过渡效果
- **ObjC 桥接**：通过 Objective-C 访问系统级硬件控制（亮度、音量）
- **Sparkle 自动更新**：内置更新框架
- **每显示器独立配置**：支持多显示器不同设置
- **可排序布局**：HUD 元素顺序可自定义

---

### 15.6 notchOS 功能优先级建议（基于本次调研）

| 优先级 | 来源 | 功能 | 理由 |
|--------|------|------|------|
| **P0** | CodeIsland | Buddy 像素猫 / 人格化设计 | 给状态面板加"灵魂"，用户粘性质变 |
| **P0** | CodeIsland | Quick Reply 按钮 | Claude 提问直接在 notch 点选，实用价值极高 |
| **P1** | Claude Island | Unix Socket 替代 HTTP | 消除 Python 后端层，降低架构复杂度和延迟 |
| **P1** | CodeIsland | 智能通知抑制 | 检测终端前台状态，避免无效打扰 |
| **P1** | CodeIsland | 5h/7d 用量统计 | 通过 Keychain 读 OAuth token，零配置 |
| **P2** | boring.notch | SkyLight 录屏隐藏 | 录屏/截图时自动隐藏 overlay |
| **P2** | Claude Island | 零配置 Hook 安装 | 首次启动自动注入，降低用户上手门槛 |
| **P2** | CodeIsland | iPhone Code Light | 独家差异化功能，但工程量大 |
| **P3** | Atoll | 手势交互 | 双指滑动替代 hover，更 intentional |
| **P3** | boring.notch | NotchShape 动画化圆角 | 精确匹配物理 notch 轮廓 |

### 15.7 架构路线思考

当前 notchOS 的 3 层架构（Swift + Python 后端 + WKWebView）在所有竞品中是**唯一使用 HTTP 中间层的**。其余项目全部走 Unix Socket 直连。

**权衡**：
- HTTP 方案的优势：Web UI 迭代快（改 CSS/JS 不需重编译），跨进程解耦好
- HTTP 方案的劣势：无法实现双向阻塞通信（权限审批所需），延迟更高，多一个进程要管理
- 如果要做权限审批，**必须引入 Unix Socket 或类似的双向阻塞通道**，HTTP fire-and-forget 无法满足

**可能的演进路径**：
1. 保留 WKWebView + Python 后端，新增 Unix Socket 仅用于权限审批的双向通信
2. 或彻底迁移到纯 Swift（参考 Claude Island / CodeIsland），放弃 Web UI 的灵活性换取架构简洁
3. 折中方案：保留 WKWebView 做展示，但用 Swift 原生 Unix Socket 替代 Python 后端
