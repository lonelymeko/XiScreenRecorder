import Foundation
import SwiftUI
import Combine

/// 屏幕录制管理器
class ScreenRecorderManager: ObservableObject {
    // MARK: - Published Properties
    @Published var recordingState: RecordingState = .idle
    @Published var recordingMode: RecordingMode = .screenAndAudio
    @Published var captureArea: CaptureArea = .fullScreen
    @Published var microphoneEnabled: Bool = false
    @Published var videoQuality: VideoQuality = .high
    @Published var frameRate: FrameRate = .fps30
    @Published var outputFormat: OutputFormat = .mp4
    @Published var customRect: CaptureRect = .zero
    @Published var elapsedTime: TimeInterval = 0
    @Published var outputPath: String = ""
    @Published var logMessages: [String] = []
    @Published var savePath: String = ""
    
    // MARK: - Devices (使用 AVDevice 结构)
    @Published var videoDevices: [AVDevice] = []
    @Published var audioDevices: [AVDevice] = []
    @Published var selectedScreenDevice: AVDevice?    // 选中的屏幕捕获设备
    @Published var selectedAudioDevice: AVDevice?     // 选中的系统音频设备 (虚拟音频)
    @Published var selectedMicDevice: AVDevice?       // 选中的麦克风设备
    @Published var autoSelectMic: Bool = true         // 自动检测麦克风
    
    // MARK: - Private Properties
    private var ffmpegProcess: Process?
    private var timer: Timer?
    private var startTime: Date?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    
    init() {
        // 设置默认保存路径到桌面
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        savePath = desktop.path
        
        // 刷新设备列表
        refreshDevices()
    }
    
    // MARK: - Device Management
    
    func refreshDevices() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let devices = FFmpegHelper.listDevices()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.videoDevices = devices.videoDevices
                self.audioDevices = devices.audioDevices
                
                // 自动选择屏幕捕获设备 (Capture screen 0, Capture screen 1, ...)
                if let screenDevice = FFmpegHelper.findScreenCaptureDevice(in: devices.videoDevices) {
                    self.selectedScreenDevice = screenDevice
                    self.addLog("🖥 自动选择屏幕设备: \(screenDevice.name) [索引 \(screenDevice.index)]")
                } else {
                    self.addLog("⚠️ 未检测到屏幕捕获设备 (Capture screen X)")
                    // 回退: 选择第一个视频设备
                    if let first = devices.videoDevices.first {
                        self.selectedScreenDevice = first
                        self.addLog("   回退使用视频设备: \(first.name) [索引 \(first.index)]")
                    }
                }
                
                // 自动检测虚拟音频设备 (BlackHole / VB-Cable / Soundflower)
                if let virtualDevice = FFmpegHelper.findVirtualAudioDevice(in: devices.audioDevices) {
                    self.selectedAudioDevice = virtualDevice
                    let deviceType = FFmpegHelper.virtualAudioDeviceType(virtualDevice.name)
                    self.addLog("🔊 自动检测到虚拟音频设备: \(deviceType) [\(virtualDevice.name)]")
                } else {
                    // 没有虚拟音频设备，选择第一个音频设备
                    self.selectedAudioDevice = devices.audioDevices.first
                    self.addLog("⚠️ 未检测到虚拟音频设备 (BlackHole / VB-Cable / Soundflower)")
                    self.addLog("   录制系统音频需要安装虚拟音频驱动")
                }
                
                // 自动检测麦克风设备
                if let micDevice = FFmpegHelper.findMicrophoneDevice(in: devices.audioDevices) {
                    self.selectedMicDevice = micDevice
                    self.addLog("🎙 自动检测到麦克风: \(micDevice.name)")
                }
                
                self.addLog("发现 \(devices.videoDevices.count) 个视频设备, \(devices.audioDevices.count) 个音频设备")
                
                // 列出所有设备
                for dev in devices.videoDevices {
                    let marker = dev.isScreenCapture ? " 🖥屏幕" : ""
                    self.addLog("  📹 [\(dev.index)] \(dev.name)\(marker)")
                }
                for dev in devices.audioDevices {
                    var marker = ""
                    if FFmpegHelper.isVirtualAudioDevice(dev.name) { marker = " ⭐虚拟音频" }
                    else if FFmpegHelper.isMicrophoneDevice(dev.name) { marker = " 🎙麦克风" }
                    self.addLog("  🔊 [\(dev.index)] \(dev.name)\(marker)")
                }
            }
        }
    }
    
    // MARK: - Recording Control
    
    func startRecording() {
        guard recordingState == .idle else { return }
        
        let format = recordingMode == .audioOnly ?
            (outputFormat.isAudioOnly ? outputFormat : .aac) :
            (outputFormat.isVideoFormat ? outputFormat : .mp4)
        
        // 生成输出文件名
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let prefix = recordingMode == .audioOnly ? "Audio" : "Screen"
        let fileName = "\(prefix)_\(timestamp).\(format.fileExtension)"
        outputPath = (savePath as NSString).appendingPathComponent(fileName)
        
        // 构建 ffmpeg 命令
        let arguments = buildFFmpegArguments()
        
        guard !arguments.isEmpty else {
            addLog("❌ 无法构建录制参数")
            return
        }
        
        addLog("📹 开始录制...")
        addLog("命令: ffmpeg \(arguments.joined(separator: " "))")
        addLog("输出: \(outputPath)")
        
        // 启动 ffmpeg 进程
        let process = Process()
        process.executableURL = URL(fileURLWithPath: FFmpegHelper.ffmpegPath())
        process.arguments = arguments
        
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()
        process.standardInput = Pipe() // 用于发送 'q' 停止录制
        
        self.errorPipe = errPipe
        
        // 异步读取 ffmpeg 输出
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.count > 0, let str = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    let lines = str.components(separatedBy: "\n").filter { !$0.isEmpty }
                    for line in lines.suffix(2) {
                        self?.addLog(line.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
        }
        
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.recordingState = .idle
                self?.stopTimer()
                self?.addLog("✅ 录制完成，文件保存至: \(self?.outputPath ?? "")")
                errPipe.fileHandleForReading.readabilityHandler = nil
            }
        }
        
        do {
            try process.run()
            self.ffmpegProcess = process
            self.recordingState = .recording
            self.startTimer()
        } catch {
            addLog("❌ 启动 ffmpeg 失败: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        guard let process = ffmpegProcess, process.isRunning else { return }
        
        addLog("⏹ 正在停止录制...")
        
        // 发送 'q' 到 ffmpeg 的 stdin 来优雅地停止
        if let inputPipe = process.standardInput as? Pipe {
            inputPipe.fileHandleForWriting.write("q".data(using: .utf8)!)
        }
        
        // 如果 3 秒后还没停止，强制终止
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
            if let process = self?.ffmpegProcess, process.isRunning {
                process.terminate()
            }
        }
    }
    
    func toggleMicrophone() {
        microphoneEnabled.toggle()
        addLog(microphoneEnabled ? "🎙 麦克风已开启" : "🎙 麦克风已关闭")
        
        if recordingState == .recording {
            addLog("⚠️ 麦克风状态将在下次录制时生效")
        }
    }
    
    func selectRegion() {
        // 最小化主窗口以避免遮挡
        if let mainWindow = NSApplication.shared.mainWindow {
            mainWindow.miniaturize(nil)
            // 等窗口最小化后再显示选择覆盖
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showRegionSelector(restoreWindow: mainWindow)
            }
        } else {
            showRegionSelector(restoreWindow: nil)
        }
    }
    
    private func showRegionSelector(restoreWindow: NSWindow?) {
        RegionSelector.selectRegion { [weak self] rect in
            DispatchQueue.main.async {
                // 恢复主窗口
                if let window = restoreWindow {
                    window.deminiaturize(nil)
                }
                
                if let rect = rect {
                    self?.customRect = rect
                    self?.captureArea = .custom
                    self?.addLog("✅ 已选择区域: \(rect.x),\(rect.y) \(rect.width)×\(rect.height)")
                } else {
                    self?.addLog("取消选择区域")
                }
            }
        }
    }
    
    func chooseSavePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择保存位置"
        
        if panel.runModal() == .OK, let url = panel.url {
            savePath = url.path
            addLog("📁 保存路径: \(savePath)")
        }
    }
    
    func openOutputFile() {
        guard !outputPath.isEmpty else { return }
        let url = URL(fileURLWithPath: outputPath)
        if FileManager.default.fileExists(atPath: outputPath) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    
    // MARK: - Build FFmpeg Arguments
    //
    // macOS avfoundation 音频录制要点:
    // 1. 系统音频需要 BlackHole/VB-Cable 等虚拟音频驱动
    // 2. avfoundation 的 -i 参数格式: "视频设备:音频设备" (可以用索引或设备名)
    // 3. 同时录系统音频+麦克风时, 需要两个独立的 -f avfoundation -i 输入,
    //    然后用 -filter_complex amix 混合音轨
    // 4. 使用设备名比索引更可靠: -i "Capture screen 0:BlackHole 16ch"
    
    private func buildFFmpegArguments() -> [String] {
        var args: [String] = []
        
        // 覆盖输出文件
        args += ["-y"]
        
        switch recordingMode {
        case .screenOnly:
            // 仅录屏, 可选麦克风
            args += buildScreenOnlyArgs()
            
        case .screenAndAudio:
            // 录屏 + 系统音频, 可选麦克风
            args += buildScreenAndAudioArgs()
            
        case .audioOnly:
            // 仅录制系统音频, 可选麦克风
            args += buildAudioOnlyArgs()
        }
        
        args += [outputPath]
        
        return args
    }
    
    /// 仅录屏 (无系统音频)
    /// 可选: 附加麦克风
    private func buildScreenOnlyArgs() -> [String] {
        guard let screenDevice = selectedScreenDevice else {
            addLog("❌ 未选择屏幕设备")
            return []
        }
        
        var args: [String] = []
        
        if microphoneEnabled, let mic = resolveMicDevice() {
            // 屏幕 + 麦克风: 合并到同一个 avfoundation 输入
            // -i "屏幕设备:麦克风设备"
            args += ["-f", "avfoundation"]
            args += ["-framerate", "\(frameRate.rawValue)"]
            args += ["-pixel_format", "uyvy422"]
            args += ["-i", "\(screenDevice.name):\(mic.name)"]
            addLog("🖥 屏幕: \(screenDevice.name) + 🎙 麦克风: \(mic.name)")
            
            // 视频编码
            args += buildVideoEncoderArgs()
            // 音频编码
            args += ["-c:a", "aac", "-b:a", "192k"]
        } else {
            // 纯屏幕, 无音频
            args += ["-f", "avfoundation"]
            args += ["-framerate", "\(frameRate.rawValue)"]
            args += ["-pixel_format", "uyvy422"]
            args += ["-i", "\(screenDevice.name):none"]
            addLog("🖥 屏幕: \(screenDevice.name) (无音频)")
            
            // 视频编码
            args += buildVideoEncoderArgs()
        }
        
        return args
    }
    
    /// 录屏 + 系统音频
    /// 可选: 附加麦克风 (使用 amix 混合两路音频)
    private func buildScreenAndAudioArgs() -> [String] {
        guard let screenDevice = selectedScreenDevice else {
            addLog("❌ 未选择屏幕设备")
            return []
        }
        guard let audioDevice = selectedAudioDevice else {
            addLog("⚠️ 未选择系统音频设备，回退到仅录屏")
            return buildScreenOnlyArgs()
        }
        
        var args: [String] = []
        
        if microphoneEnabled, let mic = resolveMicDevice(), mic != audioDevice {
            // 屏幕 + 系统音频 + 麦克风 (三路)
            // 输入0: 屏幕 + 系统音频
            // 输入1: 麦克风
            // 然后用 amix 混合两路音频
            
            // 输入 0: 屏幕视频 + 系统音频 (合并到同一个 avfoundation)
            args += ["-f", "avfoundation"]
            args += ["-framerate", "\(frameRate.rawValue)"]
            args += ["-pixel_format", "uyvy422"]
            args += ["-i", "\(screenDevice.name):\(audioDevice.name)"]
            
            // 输入 1: 麦克风 (独立的 avfoundation 输入)
            args += ["-f", "avfoundation"]
            args += ["-i", "none:\(mic.name)"]
            
            addLog("🖥 屏幕: \(screenDevice.name)")
            addLog("🔊 系统音频: \(audioDevice.name)")
            addLog("🎙 麦克风: \(mic.name)")
            addLog("🔀 使用 amix 混合系统音频 + 麦克风")
            
            // 使用 filter_complex 混合音频
            // [0:a] = 系统音频, [1:a] = 麦克风, 混合后输出 [aout]
            var filterParts = "[0:a][1:a]amix=inputs=2:duration=longest[aout]"
            
            // 如果有视频裁剪, 加入 crop 滤镜
            if captureArea == .custom && customRect.isValid {
                let r = customRect.normalized
                filterParts = "[0:v]crop=\(r.width):\(r.height):\(r.x):\(r.y)[vout];\(filterParts)"
                args += ["-filter_complex", filterParts]
                args += ["-map", "[vout]", "-map", "[aout]"]
            } else {
                args += ["-filter_complex", filterParts]
                args += ["-map", "0:v", "-map", "[aout]"]
            }
            
            // 编码
            args += ["-c:v", "libx264", "-preset", "ultrafast"]
            args += ["-crf", videoQuality.crf, "-pix_fmt", "yuv420p", "-g", "60"]
            args += ["-c:a", "aac", "-b:a", "192k"]
            
        } else {
            // 屏幕 + 系统音频 (无麦克风)
            // 合并到同一个 avfoundation 输入: "屏幕设备:音频设备"
            args += ["-f", "avfoundation"]
            args += ["-framerate", "\(frameRate.rawValue)"]
            args += ["-pixel_format", "uyvy422"]
            args += ["-i", "\(screenDevice.name):\(audioDevice.name)"]
            
            addLog("🖥 屏幕: \(screenDevice.name)")
            addLog("🔊 系统音频: \(audioDevice.name)")
            
            // 编码
            args += buildVideoEncoderArgs()
            args += ["-c:a", "aac", "-b:a", "192k"]
        }
        
        return args
    }
    
    /// 仅录制系统音频
    /// 可选: 附加麦克风 (使用 amix 混合)
    private func buildAudioOnlyArgs() -> [String] {
        guard let audioDevice = selectedAudioDevice else {
            addLog("⚠️ 未选择系统音频设备")
            return []
        }
        
        var args: [String] = []
        
        if microphoneEnabled, let mic = resolveMicDevice(), mic != audioDevice {
            // 系统音频 + 麦克风, 混合两路
            
            // 输入 0: 系统音频 (通过 BlackHole 等)
            args += ["-f", "avfoundation"]
            args += ["-i", "none:\(audioDevice.name)"]
            
            // 输入 1: 麦克风
            args += ["-f", "avfoundation"]
            args += ["-i", "none:\(mic.name)"]
            
            addLog("🔊 系统音频: \(audioDevice.name)")
            addLog("🎙 麦克风: \(mic.name)")
            addLog("🔀 使用 amix 混合系统音频 + 麦克风")
            
            // amix 混合
            args += ["-filter_complex", "[0:a][1:a]amix=inputs=2:duration=longest[aout]"]
            args += ["-map", "[aout]"]
            
            // 音频编码
            args += buildAudioEncoderArgs()
            
        } else {
            // 仅系统音频
            // 格式: -i "none:设备名"  (无视频, 只采音频)
            args += ["-f", "avfoundation"]
            args += ["-i", "none:\(audioDevice.name)"]
            
            addLog("🔊 系统音频: \(audioDevice.name)")
            
            // 音频编码
            args += buildAudioEncoderArgs()
        }
        
        return args
    }
    
    /// 解析实际使用的麦克风设备
    private func resolveMicDevice() -> AVDevice? {
        var mic: AVDevice?
        
        if autoSelectMic {
            mic = FFmpegHelper.findMicrophoneDevice(in: audioDevices)
        } else {
            mic = selectedMicDevice
        }
        
        guard let result = mic else {
            addLog("⚠️ 未找到麦克风设备")
            return nil
        }
        
        // 确保和系统音频不是同一个设备
        if let audioDevice = selectedAudioDevice, result == audioDevice {
            if let alt = audioDevices.first(where: { $0 != audioDevice && !FFmpegHelper.isVirtualAudioDevice($0.name) }) {
                addLog("🎙 麦克风与系统音频相同，切换到: \(alt.name)")
                return alt
            }
            addLog("⚠️ 麦克风与系统音频为同一设备，无法同时使用")
            return nil
        }
        
        return result
    }
    
    /// 视频编码参数 (用于简单场景, 不含 filter_complex)
    private func buildVideoEncoderArgs() -> [String] {
        var args: [String] = []
        
        args += ["-c:v", "libx264"]
        args += ["-preset", "ultrafast"]
        args += ["-crf", videoQuality.crf]
        args += ["-pix_fmt", "yuv420p"]
        args += ["-g", "60"]
        
        // 裁剪区域
        if captureArea == .custom && customRect.isValid {
            let r = customRect.normalized
            args += ["-vf", "crop=\(r.width):\(r.height):\(r.x):\(r.y)"]
        }
        
        return args
    }
    
    /// 音频编码参数
    private func buildAudioEncoderArgs() -> [String] {
        if outputFormat == .mp3 {
            return ["-c:a", "libmp3lame", "-b:a", "320k"]
        } else {
            return ["-c:a", "aac", "-b:a", "256k"]
        }
    }
    
    // MARK: - Timer
    
    private func startTimer() {
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.startTime else { return }
            self.elapsedTime = Date().timeIntervalSince(startTime)
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Logging
    
    func addLog(_ message: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        let timestamp = dateFormatter.string(from: Date())
        let logLine = "[\(timestamp)] \(message)"
        
        // 保持最近 100 条日志
        if logMessages.count > 100 {
            logMessages.removeFirst()
        }
        logMessages.append(logLine)
    }
    
    // MARK: - Helpers
    
    var formattedElapsedTime: String {
        let hours = Int(elapsedTime) / 3600
        let minutes = (Int(elapsedTime) % 3600) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
