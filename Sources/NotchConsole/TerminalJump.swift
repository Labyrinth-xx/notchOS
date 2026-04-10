import AppKit

/// Jumps to the terminal window/tab associated with a Claude Code session.
/// Uses NSRunningApplication for activation and AppleScript for precise tab targeting.
enum TerminalJump {

    /// Known terminal bundle IDs
    private static let terminalBundleIDs: [String: String] = [
        "com.apple.Terminal": "Terminal",
        "com.googlecode.iterm2": "iTerm2",
        "com.mitchellh.ghostty": "Ghostty",
        "net.kovidgoyal.kitty": "kitty",
        "dev.warp.Warp-Stable": "Warp",
        "com.microsoft.VSCode": "VS Code",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.github.nicklockwood.iVersion.dev.zed.Zed": "Zed",
        "dev.zed.Zed": "Zed",
        "org.alacritty": "Alacritty",
    ]

    /// Attempt to jump to the terminal running a given session.
    /// Falls back to activating any running terminal if precise matching fails.
    static func jump(sessionId: String?, cwd: String?) {
        // Try to find a running terminal application
        let running = NSWorkspace.shared.runningApplications
        var activated = false

        for app in running {
            guard let bundleId = app.bundleIdentifier,
                  terminalBundleIDs[bundleId] != nil else { continue }

            // Try AppleScript-based precise jump for iTerm2
            if bundleId == "com.googlecode.iterm2", let dir = cwd, !dir.isEmpty {
                if jumpToITerm2Session(cwd: dir) {
                    activated = true
                    break
                }
            }

            // Generic activation (brings terminal to front)
            app.activate()
            activated = true
            break
        }

        // If no terminal found, try to open Terminal.app
        if !activated {
            let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            NSWorkspace.shared.open(terminalURL)
        }
    }

    /// Sanitize a string for safe interpolation into AppleScript string literals.
    private static func sanitizeForAppleScript(_ str: String) -> String {
        str.replacing("\\", with: "\\\\")
           .replacing("\"", with: "\\\"")
           .filter { !$0.isNewline && $0.asciiValue.map { $0 >= 32 } ?? true }
    }

    /// iTerm2-specific: find and activate the session whose current directory matches cwd.
    private static func jumpToITerm2Session(cwd: String) -> Bool {
        let safeCwd = sanitizeForAppleScript(cwd)
        let script = """
        tell application "iTerm2"
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if (variable named "path" of aSession) contains "\(safeCwd)" then
                            select aTab
                            select aSession
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            return result.booleanValue
        }
        return false
    }
}
