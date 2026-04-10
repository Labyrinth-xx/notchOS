import AppKit
import WebKit

/// Monitors macOS Now Playing info via MediaRemote private framework.
/// Polls periodically and injects data into WKWebView via JS bridge.
final class NowPlayingMonitor {
    private weak var webView: WKWebView?
    private var pollTimer: Timer?
    private var isPlaying = false

    // MediaRemote function pointers (loaded dynamically)
    private typealias MRNowPlayingInfoCallback = @convention(c) (CFDictionary) -> Void
    private var mrGetNowPlayingInfo: (@convention(c) (DispatchQueue, @escaping (CFDictionary) -> Void) -> Void)?
    private var mrSendCommand: (@convention(c) (UInt32, UnsafeMutableRawPointer?) -> Bool)?
    private var frameworkHandle: UnsafeMutableRawPointer?
    private var frameworkLoaded = false

    // MediaRemote command constants
    static let mrCommandTogglePlayPause: UInt32 = 2
    static let mrCommandNextTrack: UInt32 = 4
    static let mrCommandPreviousTrack: UInt32 = 5

    init(webView: WKWebView) {
        self.webView = webView
        loadFramework()
        startPolling()
    }

    // MARK: - Framework Loading

    deinit {
        stop()
        if let handle = frameworkHandle { dlclose(handle) }
    }

    private func loadFramework() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        ) else { return }
        frameworkHandle = handle

        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            mrGetNowPlayingInfo = unsafeBitCast(
                sym,
                to: (@convention(c) (DispatchQueue, @escaping (CFDictionary) -> Void) -> Void).self
            )
        }

        if let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            mrSendCommand = unsafeBitCast(
                sym,
                to: (@convention(c) (UInt32, UnsafeMutableRawPointer?) -> Bool).self
            )
        }

        frameworkLoaded = mrGetNowPlayingInfo != nil
    }

    // MARK: - Polling

    private func startPolling() {
        poll()
        scheduleNext()
    }

    private func scheduleNext() {
        let interval: TimeInterval = isPlaying ? 3.0 : 10.0
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.poll()
            self?.scheduleNext()
        }
    }

    private func poll() {
        guard frameworkLoaded, let getInfo = mrGetNowPlayingInfo else {
            injectEmpty()
            return
        }

        getInfo(DispatchQueue.main) { [weak self] info in
            self?.handleNowPlayingInfo(info as NSDictionary)
        }
    }

    private func handleNowPlayingInfo(_ info: NSDictionary) {
        let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String
        let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String
        let duration = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0
        let elapsed = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
        let playbackRate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0

        let playing = playbackRate > 0
        isPlaying = playing

        guard let trackTitle = title, !trackTitle.isEmpty else {
            injectEmpty()
            return
        }

        // Build artwork data URL (base64 JPEG, small thumbnail)
        var artworkDataURL = "null"
        if let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            if let image = NSImage(data: artworkData) {
                let thumbSize = NSSize(width: 64, height: 64)
                if let thumb = resizeImage(image, to: thumbSize),
                   let jpegData = thumb.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: jpegData),
                   let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) {
                    let b64 = jpeg.base64EncodedString()
                    artworkDataURL = "\"data:image/jpeg;base64,\(b64)\""
                }
            }
        }

        let js = """
        window.notchUpdateMusic && window.notchUpdateMusic({
          title: \(jsonString(trackTitle)),
          artist: \(jsonString(artist ?? "")),
          album: \(jsonString(album ?? "")),
          duration: \(duration),
          elapsed: \(elapsed),
          isPlaying: \(playing),
          artwork: \(artworkDataURL)
        });
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    private func injectEmpty() {
        let js = "window.notchUpdateMusic && window.notchUpdateMusic(null);"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Media Commands

    func sendCommand(_ command: UInt32) {
        _ = mrSendCommand?(command, nil)
    }

    // MARK: - Helpers

    private func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()
        return newImage
    }

    private func jsonString(_ str: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: str),
              let result = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return result
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
