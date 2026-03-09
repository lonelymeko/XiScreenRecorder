import SwiftUI
import AppKit

@main
struct ScreenRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var recorder = ScreenRecorderManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recorder)
                // .frame(minWidth: 680, minHeight: 632)
                // .frame(maxWidth: 680, maxHeight: 632)
                .frame(width: 680, height: 632)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let window = NSApplication.shared.windows.first {
                window.makeKeyAndOrderFront(nil)
                window.center()
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.isMovableByWindowBackground = true
                
                // 监听窗口大小变化
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(self.windowDidResize(_:)),
                    name: NSWindow.didResizeNotification,
                    object: window
                )
            }
        }
        
        // 检查 ffmpeg
        if FFmpegHelper.isFFmpegAvailable() {
            print("✅ FFmpeg found at: \(FFmpegHelper.ffmpegPath())")
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showFFmpegDownloadAlert()
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    @objc func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            let frame = window.frame
            print("📐 窗口大小变化: \(Int(frame.size.width)) × \(Int(frame.size.height))  origin: (\(Int(frame.origin.x)), \(Int(frame.origin.y)))")
        }
    }
    
    private func showFFmpegDownloadAlert() {
        let alert = NSAlert()
        alert.messageText = "未检测到 FFmpeg"
        alert.informativeText = "Screen Recorder 需要 FFmpeg 来录制屏幕和音频。\n\n是否自动下载安装？（如有 Homebrew 将优先使用 brew install ffmpeg）"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "自动安装")
        alert.addButton(withTitle: "稍后手动安装")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            showDownloadProgress()
        }
    }
    
    private func showDownloadProgress() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "安装 FFmpeg"
        panel.center()
        panel.isFloatingPanel = true
        
        let progressView = NSProgressIndicator(frame: NSRect(x: 20, y: 60, width: 380, height: 20))
        progressView.style = .bar
        progressView.isIndeterminate = true
        progressView.startAnimation(nil)
        
        let label = NSTextField(labelWithString: "正在准备...")
        label.frame = NSRect(x: 20, y: 30, width: 380, height: 20)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 140))
        
        let titleLabel = NSTextField(labelWithString: "正在安装 FFmpeg，请稍候...")
        titleLabel.frame = NSRect(x: 20, y: 95, width: 380, height: 25)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        
        container.addSubview(titleLabel)
        container.addSubview(progressView)
        container.addSubview(label)
        panel.contentView = container
        panel.makeKeyAndOrderFront(nil)
        
        FFmpegHelper.downloadFFmpeg { status in
            label.stringValue = status
        } completion: { success in
            progressView.stopAnimation(nil)
            
            if success {
                label.stringValue = "✅ 安装成功! FFmpeg: \(FFmpegHelper.ffmpegPath())"
                titleLabel.stringValue = "安装完成"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    panel.orderOut(nil)
                }
            } else {
                titleLabel.stringValue = "安装失败"
                label.stringValue = "请手动安装: brew install ffmpeg"
            }
        }
    }
}
