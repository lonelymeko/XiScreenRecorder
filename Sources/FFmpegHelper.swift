import Foundation
import AppKit

/// 设备信息结构
struct AVDevice: Identifiable, Equatable {
    let index: Int       // ffmpeg avfoundation 索引
    let name: String     // 设备名称
    var id: Int { index }
    
    /// 是否是屏幕捕获设备 (Capture screen 0, Capture screen 1, ...)
    var isScreenCapture: Bool {
        return name.lowercased().hasPrefix("capture screen")
    }
    
    /// 提取屏幕编号 (Capture screen 0 -> 0)
    var screenIndex: Int? {
        guard isScreenCapture else { return nil }
        let parts = name.components(separatedBy: " ")
        return parts.last.flatMap { Int($0) }
    }
}

/// FFmpeg 辅助工具类
class FFmpegHelper {
    
    /// FFmpeg 常见安装路径 (App bundle 内 PATH 可能不完整, 需要逐个检查)
    private static let ffmpegSearchPaths = [
        "/opt/homebrew/bin/ffmpeg",      // Homebrew (Apple Silicon)
        "/usr/local/bin/ffmpeg",         // Homebrew (Intel) / 手动安装
        "/usr/bin/ffmpeg",               // 系统路径
        "/opt/local/bin/ffmpeg",         // MacPorts
    ]
    
    /// 应用内置 ffmpeg 存储路径
    static var bundledFFmpegPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ScreenRecorder")
        return dir.appendingPathComponent("ffmpeg").path
    }
    
    /// 检查 FFmpeg 是否可用
    static func isFFmpegAvailable() -> Bool {
        return !ffmpegPath().isEmpty
    }
    
    /// 获取 ffmpeg 路径 (优先检查已知路径, 再 fallback 到 which)
    static func ffmpegPath() -> String {
        // 0. 检查应用内下载的 ffmpeg
        if FileManager.default.isExecutableFile(atPath: bundledFFmpegPath) {
            return bundledFFmpegPath
        }
        
        // 1. 先检查常见安装路径 (App bundle 中 PATH 不可靠)
        for path in ffmpegSearchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        // 2. 尝试通过 shell 查找 (设置完整 PATH)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which ffmpeg"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {}
        
        return ""
    }
    
    // MARK: - FFmpeg 自动下载
    
    /// 使用 Homebrew 安装 ffmpeg (在终端中执行)
    static func downloadFFmpeg(progress: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        let destDir = (bundledFFmpegPath as NSString).deletingLastPathComponent
        
        // 确保目录存在
        try? FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        
        progress("正在检测系统架构...")
        
        // 用 Homebrew 安装是最可靠的方式
        // 但如果用户没有 Homebrew，我们下载静态编译版本
        
        // 先试 Homebrew
        let brewCheck = Process()
        brewCheck.executableURL = URL(fileURLWithPath: "/bin/zsh")
        brewCheck.arguments = ["-l", "-c", "which brew"]
        let brewPipe = Pipe()
        brewCheck.standardOutput = brewPipe
        brewCheck.standardError = Pipe()
        
        do {
            try brewCheck.run()
            brewCheck.waitUntilExit()
        } catch {}
        
        let brewData = brewPipe.fileHandleForReading.readDataToEndOfFile()
        let brewPath = String(data: brewData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasBrew = !brewPath.isEmpty
        
        if hasBrew {
            progress("检测到 Homebrew，正在安装 ffmpeg（可能需要几分钟）...")
            
            DispatchQueue.global(qos: .userInitiated).async {
                let install = Process()
                install.executableURL = URL(fileURLWithPath: "/bin/zsh")
                install.arguments = ["-l", "-c", "\(brewPath) install ffmpeg 2>&1"]
                let installPipe = Pipe()
                install.standardOutput = installPipe
                install.standardError = installPipe
                
                installPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                        let lines = str.components(separatedBy: "\n")
                        if let last = lines.last(where: { !$0.isEmpty }) {
                            DispatchQueue.main.async { progress(last) }
                        }
                    }
                }
                
                do {
                    try install.run()
                    install.waitUntilExit()
                    installPipe.fileHandleForReading.readabilityHandler = nil
                    
                    let success = install.terminationStatus == 0
                    DispatchQueue.main.async {
                        if success || isFFmpegAvailable() {
                            progress("✅ FFmpeg 安装成功!")
                            completion(true)
                        } else {
                            progress("❌ Homebrew 安装失败，尝试下载静态版本...")
                            downloadStaticFFmpeg(destDir: destDir, progress: progress, completion: completion)
                        }
                    }
                } catch {
                    installPipe.fileHandleForReading.readabilityHandler = nil
                    DispatchQueue.main.async {
                        progress("❌ Homebrew 安装失败: \(error.localizedDescription)")
                        downloadStaticFFmpeg(destDir: destDir, progress: progress, completion: completion)
                    }
                }
            }
        } else {
            // 没有 Homebrew，直接下载静态二进制
            progress("未检测到 Homebrew，正在下载 ffmpeg 静态版本...")
            downloadStaticFFmpeg(destDir: destDir, progress: progress, completion: completion)
        }
    }
    
    /// 下载静态编译的 ffmpeg 二进制
    private static func downloadStaticFFmpeg(destDir: String, progress: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        // evermeet.cx 提供 macOS 静态编译的 ffmpeg
        let downloadURL = "https://evermeet.cx/ffmpeg/getrelease/zip"
        
        guard let url = URL(string: downloadURL) else {
            progress("❌ 下载 URL 无效")
            completion(false)
            return
        }
        
        progress("正在从 evermeet.cx 下载 ffmpeg...")
        
        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    progress("❌ 下载失败: \(error.localizedDescription)")
                    completion(false)
                }
                return
            }
            
            guard let tempURL = tempURL else {
                DispatchQueue.main.async {
                    progress("❌ 下载失败: 无临时文件")
                    completion(false)
                }
                return
            }
            
            DispatchQueue.main.async { progress("下载完成，正在解压...") }
            
            // 解压 zip
            let zipPath = tempURL.path
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", zipPath, "-d", destDir]
            unzipProcess.standardOutput = Pipe()
            unzipProcess.standardError = Pipe()
            
            do {
                try unzipProcess.run()
                unzipProcess.waitUntilExit()
                
                // 设置可执行权限
                let dest = bundledFFmpegPath
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest)
                
                let success = FileManager.default.isExecutableFile(atPath: dest)
                DispatchQueue.main.async {
                    if success {
                        progress("✅ FFmpeg 下载并安装成功!")
                    } else {
                        progress("❌ 解压后未找到 ffmpeg 可执行文件")
                    }
                    completion(success)
                }
            } catch {
                DispatchQueue.main.async {
                    progress("❌ 解压失败: \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
        task.resume()
    }
    
    /// 列出所有可用的 AVFoundation 设备（返回结构化设备信息，包含正确索引）
    static func listDevices() -> (videoDevices: [AVDevice], audioDevices: [AVDevice]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath())
        process.arguments = ["-f", "avfoundation", "-list_devices", "true", "-i", ""]
        
        let pipe = Pipe()
        process.standardError = pipe  // ffmpeg 设备列表输出到 stderr
        process.standardOutput = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ([], [])
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        return parseDeviceList(output)
    }
    
    /// 解析 ffmpeg -list_devices 的输出
    /// 格式: [AVFoundation indev @ 0x...] [index] DeviceName
    static func parseDeviceList(_ output: String) -> (videoDevices: [AVDevice], audioDevices: [AVDevice]) {
        var videoDevices: [AVDevice] = []
        var audioDevices: [AVDevice] = []
        var isVideo = false
        var isAudio = false
        
        for line in output.components(separatedBy: "\n") {
            if line.contains("AVFoundation video devices:") {
                isVideo = true
                isAudio = false
                continue
            }
            if line.contains("AVFoundation audio devices:") {
                isVideo = false
                isAudio = true
                continue
            }
            
            // 按 "] " 分割，与 Go 代码相同的解析方式
            let parts = line.components(separatedBy: "] ")
            if parts.count >= 3 {
                // parts[1] 是 "[index" 形式
                let indexPart = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                // parts[2:] 拼回来是设备名称
                let deviceName = parts.dropFirst(2).joined(separator: "] ").trimmingCharacters(in: .whitespaces)
                
                if let index = Int(indexPart), !deviceName.isEmpty {
                    let device = AVDevice(index: index, name: deviceName)
                    if isVideo {
                        videoDevices.append(device)
                    } else if isAudio {
                        audioDevices.append(device)
                    }
                }
            }
        }
        
        return (videoDevices, audioDevices)
    }
    
    /// 已知的虚拟音频设备关键字（用于捕获系统音频）
    static let virtualAudioKeywords = [
        "blackhole",
        "vb-cable", "vbcable", "vb cable",
        "soundflower",
        "loopback",
        "virtual cable",
        "cable output",
        "aggregate",       // 聚合设备 (Aggregate Device)
        "multi-output",    // 多输出设备
    ]
    
    /// 已知的麦克风设备关键字
    static let microphoneKeywords = [
        "microphone", "麦克风", "mic",
        "built-in", "内置",
        "external mic", "headset",
    ]
    
    /// 判断设备名称是否是虚拟音频设备（可用于捕获系统音频）
    static func isVirtualAudioDevice(_ deviceName: String) -> Bool {
        let lower = deviceName.lowercased()
        return virtualAudioKeywords.contains { lower.contains($0) }
    }
    
    /// 判断设备名称是否是麦克风设备
    static func isMicrophoneDevice(_ deviceName: String) -> Bool {
        let lower = deviceName.lowercased()
        return microphoneKeywords.contains { lower.contains($0) }
    }
    
    /// 在设备列表中查找第一个屏幕捕获设备
    static func findScreenCaptureDevice(in devices: [AVDevice]) -> AVDevice? {
        return devices.first { $0.isScreenCapture }
    }
    
    /// 在设备列表中查找虚拟音频设备
    static func findVirtualAudioDevice(in devices: [AVDevice]) -> AVDevice? {
        return devices.first { isVirtualAudioDevice($0.name) }
    }
    
    /// 在设备列表中查找麦克风设备
    static func findMicrophoneDevice(in devices: [AVDevice]) -> AVDevice? {
        return devices.first { isMicrophoneDevice($0.name) }
    }
    
    /// 获取虚拟音频设备类型描述
    static func virtualAudioDeviceType(_ deviceName: String) -> String {
        let lower = deviceName.lowercased()
        if lower.contains("blackhole") { return "BlackHole" }
        if lower.contains("vb-cable") || lower.contains("vbcable") || lower.contains("vb cable") || lower.contains("cable") { return "VB-Cable" }
        if lower.contains("soundflower") { return "Soundflower" }
        if lower.contains("loopback") { return "Loopback" }
        if lower.contains("aggregate") { return "聚合设备" }
        if lower.contains("multi-output") { return "多输出设备" }
        return "虚拟音频设备"
    }
    
    /// 获取主显示器分辨率
    static func mainScreenResolution() -> (width: Int, height: Int) {
        if let screen = NSScreen.main {
            let frame = screen.frame
            let scale = screen.backingScaleFactor
            return (Int(frame.width * scale), Int(frame.height * scale))
        }
        return (1920, 1080)
    }
    
    /// 获取主显示器逻辑分辨率
    static func mainScreenLogicalResolution() -> (width: Int, height: Int) {
        if let screen = NSScreen.main {
            let frame = screen.frame
            return (Int(frame.width), Int(frame.height))
        }
        return (1920, 1080)
    }
}
