import SwiftUI

// MARK: - 侧边栏导航项
enum SidebarPage: String, CaseIterable, Identifiable {
    case recording = "录制模式"
    case screen = "屏幕"
    case audio = "音频"
    case video = "视频"
    case output = "输出"
    case log = "日志"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .recording: return "record.circle"
        case .screen:    return "display"
        case .audio:     return "speaker.wave.2.fill"
        case .video:     return "film"
        case .output:    return "doc.fill"
        case .log:       return "terminal"
        }
    }

    var color: Color {
        switch self {
        case .recording: return .red
        case .screen:    return .blue
        case .audio:     return .purple
        case .video:     return .orange
        case .output:    return .teal
        case .log:       return .green
        }
    }
}

// MARK: - 主界面 (仿 macOS 系统设置左右分栏)
struct ContentView: View {
    @EnvironmentObject var recorder: ScreenRecorderManager
    @State private var selectedPage: SidebarPage = .recording

    var body: some View {
        NavigationSplitView {
            // ========== 左侧边栏 ==========
            List(selection: $selectedPage) {
                Section("通用") {
                    sidebarRow(.recording)
                    sidebarRow(.screen)
                    sidebarRow(.audio)
                }
                Section("高级") {
                    sidebarRow(.video)
                    sidebarRow(.output)
                }
                Section {
                    sidebarRow(.log)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    sidebarFooter
                }
            }
        } detail: {
            // ========== 右侧详情 ==========
            VStack(spacing: 0) {
                ScrollView {
                    detailContent
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                bottomBar
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func sidebarRow(_ page: SidebarPage) -> some View {
        Label {
            Text(page.rawValue)
        } icon: {
            Image(systemName: page.icon)
                .foregroundColor(page.color)
        }
        .tag(page)
    }

    // MARK: 侧边栏底部状态
    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
            Text(recorder.recordingState.displayText)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if recorder.recordingState == .recording {
                Text(recorder.formattedElapsedTime)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var stateColor: Color {
        switch recorder.recordingState {
        case .idle: return .secondary
        case .recording: return .red
        case .paused: return .orange
        }
    }

    // MARK: 右侧详情内容路由
    @ViewBuilder
    private var detailContent: some View {
        switch selectedPage {
        case .recording: RecordingPage()
        case .screen:    ScreenPage()
        case .audio:     AudioPage()
        case .video:     VideoPage()
        case .output:    OutputPage()
        case .log:       LogPage()
        }
    }

    // MARK: 底部控制栏
    private var bottomBar: some View {
        HStack(spacing: 14) {
            // 麦克风 — 点击弹出设备选择菜单
            Menu {
                // 开关
                Button(action: { recorder.toggleMicrophone() }) {
                    if recorder.microphoneEnabled {
                        Label("关闭麦克风", systemImage: "mic.slash")
                    } else {
                        Label("开启麦克风", systemImage: "mic.fill")
                    }
                }
                
                Divider()
                
                // 自动选择
                Button(action: {
                    recorder.microphoneEnabled = true
                    recorder.autoSelectMic = true
                }) {
                    HStack {
                        Text("自动检测")
                        if recorder.microphoneEnabled && recorder.autoSelectMic {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Divider()
                
                // 设备列表
                let micDevices = recorder.audioDevices.filter { FFmpegHelper.isMicrophoneDevice($0.name) }
                let otherDevices = recorder.audioDevices.filter { !FFmpegHelper.isMicrophoneDevice($0.name) }
                
                if !micDevices.isEmpty {
                    Section("麦克风设备") {
                        ForEach(micDevices) { device in
                            Button(action: {
                                recorder.microphoneEnabled = true
                                recorder.autoSelectMic = false
                                recorder.selectedMicDevice = device
                            }) {
                                HStack {
                                    Text(device.name)
                                    if !recorder.autoSelectMic && device == recorder.selectedMicDevice {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                
                if !otherDevices.isEmpty {
                    Section("其他设备") {
                        ForEach(otherDevices) { device in
                            Button(action: {
                                recorder.microphoneEnabled = true
                                recorder.autoSelectMic = false
                                recorder.selectedMicDevice = device
                            }) {
                                HStack {
                                    Text(device.name)
                                    if !recorder.autoSelectMic && device == recorder.selectedMicDevice {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: recorder.microphoneEnabled ? "mic.fill" : "mic.slash.fill")
                        .font(.title3)
                        .foregroundColor(recorder.microphoneEnabled ? .green : .secondary)
                    Image(systemName: "chevron.up")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("选择麦克风")

            if !recorder.outputPath.isEmpty && recorder.recordingState == .idle {
                Button(action: { recorder.openOutputFile() }) {
                    Image(systemName: "folder")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("在 Finder 中显示")
            }

            Spacer()

            // 录制按钮
            if recorder.recordingState == .idle {
                Button(action: { recorder.startRecording() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "record.circle")
                        Text("开始录制")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.red))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: { recorder.stopRecording() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.circle.fill")
                        Text("停止录制  \(recorder.formattedElapsedTime)")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - 通用表单组件 (仿系统设置样式)
// ────────────────────────────────────────────────────────────────────

/// 页面标题
struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title)
                .fontWeight(.bold)
            Text(subtitle)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 4)
    }
}

/// 分组卡片 (仿系统设置圆角卡片)
struct FormCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

/// 卡片内的一行
struct FormRow<Accessory: View>: View {
    let icon: String?
    let iconColor: Color
    let title: String
    let subtitle: String?
    let showSeparator: Bool
    let accessory: Accessory

    init(
        icon: String? = nil,
        iconColor: Color = .accentColor,
        title: String,
        subtitle: String? = nil,
        showSeparator: Bool = true,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.showSeparator = showSeparator
        self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundColor(iconColor)
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                accessory
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            if showSeparator {
                Divider().padding(.leading, icon != nil ? 46 : 12)
            }
        }
    }
}

/// 分组标签
struct FormSectionLabel: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - 页面：录制模式
// ────────────────────────────────────────────────────────────────────
struct RecordingPage: View {
    @EnvironmentObject var recorder: ScreenRecorderManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "录制模式", subtitle: "选择你需要录制的内容")

            FormCard {
                ForEach(Array(RecordingMode.allCases.enumerated()), id: \.element.id) { i, mode in
                    let isLast = i == RecordingMode.allCases.count - 1
                    Button(action: { recorder.recordingMode = mode }) {
                        modeRow(mode, isSelected: recorder.recordingMode == mode, showSep: !isLast)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 当前模式描述
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text(recorder.recordingMode.description)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private func modeRow(_ mode: RecordingMode, isSelected: Bool, showSep: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 26)
                Text(mode.rawValue)
                    .foregroundColor(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            if showSep { Divider().padding(.leading, 50) }
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - 页面：屏幕
// ────────────────────────────────────────────────────────────────────
struct ScreenPage: View {
    @EnvironmentObject var recorder: ScreenRecorderManager

    var screenDevices: [AVDevice] {
        recorder.videoDevices.filter { $0.isScreenCapture }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "屏幕", subtitle: "选择要录制的屏幕和区域")

            if recorder.recordingMode == .audioOnly {
                noScreenHint
            } else {
                screenDeviceCard
                captureAreaCard
            }
        }
    }

    private var noScreenHint: some View {
        FormCard {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("当前为「仅音频」模式，无需选择屏幕。")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding(14)
        }
    }

    // 屏幕设备卡片
    private var screenDeviceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            FormSectionLabel(title: "屏幕设备")
            FormCard {
                if screenDevices.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("未检测到屏幕捕获设备")
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                } else {
                    ForEach(Array(screenDevices.enumerated()), id: \.element.id) { i, device in
                        let isSelected = device == recorder.selectedScreenDevice
                        let isLast = i == screenDevices.count - 1
                        Button(action: { recorder.selectedScreenDevice = device }) {
                            FormRow(
                                icon: "display",
                                iconColor: isSelected ? .accentColor : .secondary,
                                title: device.name,
                                subtitle: "索引 \(device.index)",
                                showSeparator: !isLast
                            ) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // 捕获区域卡片
    private var captureAreaCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            FormSectionLabel(title: "捕获区域")
            FormCard {
                HStack(spacing: 0) {
                    ForEach(Array(CaptureArea.allCases.enumerated()), id: \.element.id) { i, area in
                        let isSelected = recorder.captureArea == area

                        Button(action: {
                            if area == .custom { recorder.selectRegion() }
                            else { recorder.captureArea = area }
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: area.icon)
                                    .font(.title2)
                                Text(area.rawValue)
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                            .foregroundColor(isSelected ? .accentColor : .primary)
                        }
                        .buttonStyle(.plain)

                        if i < CaptureArea.allCases.count - 1 {
                            Divider().frame(height: 40)
                        }
                    }
                }

                if recorder.captureArea == .custom && recorder.customRect.isValid {
                    Divider()
                    HStack(spacing: 8) {
                        Image(systemName: "viewfinder")
                            .foregroundColor(.blue)
                        Text("\(recorder.customRect.width) × \(recorder.customRect.height)")
                            .font(.system(.callout, design: .monospaced))
                        Text("偏移 (\(recorder.customRect.x), \(recorder.customRect.y))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("重新选择") { recorder.selectRegion() }
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - 页面：音频
// ────────────────────────────────────────────────────────────────────
struct AudioPage: View {
    @EnvironmentObject var recorder: ScreenRecorderManager

    var needsSystemAudio: Bool {
        recorder.recordingMode == .screenAndAudio || recorder.recordingMode == .audioOnly
    }
    var hasVirtualAudio: Bool {
        FFmpegHelper.findVirtualAudioDevice(in: recorder.audioDevices) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "音频", subtitle: "系统音频和麦克风设置")

            // 多输出设备提醒
            if needsSystemAudio {
                MultiOutputSetupHint(hasVirtualAudio: hasVirtualAudio)
            }

            // 系统音频设备
            VStack(alignment: .leading, spacing: 6) {
                FormSectionLabel(title: "系统音频设备")
                if recorder.audioDevices.isEmpty {
                    FormCard {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("未检测到音频设备")
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                    }
                } else {
                    FormCard {
                        ForEach(Array(recorder.audioDevices.enumerated()), id: \.element.id) { i, device in
                            let isVirtual = FFmpegHelper.isVirtualAudioDevice(device.name)
                            let isSelected = device == recorder.selectedAudioDevice
                            let isLast = i == recorder.audioDevices.count - 1

                            Button(action: { recorder.selectedAudioDevice = device }) {
                                VStack(spacing: 0) {
                                    HStack(spacing: 10) {
                                        Image(systemName: isVirtual ? "waveform.circle.fill" : "speaker.wave.2")
                                            .foregroundColor(isSelected ? .accentColor : .secondary)
                                            .frame(width: 24)
                                        VStack(alignment: .leading, spacing: 1) {
                                            HStack(spacing: 6) {
                                                Text(device.name)
                                                if isVirtual {
                                                    Text(FFmpegHelper.virtualAudioDeviceType(device.name))
                                                        .font(.caption2)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1)
                                                        .background(Capsule().fill(Color.green.opacity(0.15)))
                                                        .foregroundColor(.green)
                                                }
                                            }
                                            Text("索引 \(device.index)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                    .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                                    if !isLast { Divider().padding(.leading, 46) }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        // 虚拟音频检测状态
                        if hasVirtualAudio {
                            Label("已检测到虚拟音频", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundColor(.green)
                        } else {
                            Label("需要 BlackHole / VB-Cable", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundColor(.orange)
                        }
                        Spacer()
                        Button(action: { recorder.refreshDevices() }) {
                            Label("刷新", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            // 麦克风
            VStack(alignment: .leading, spacing: 6) {
                FormSectionLabel(title: "麦克风")
                FormCard {
                    FormRow(icon: "mic.fill", iconColor: recorder.microphoneEnabled ? .green : .secondary,
                            title: "启用麦克风", showSeparator: recorder.microphoneEnabled) {
                        Toggle("", isOn: $recorder.microphoneEnabled).labelsHidden()
                    }

                    if recorder.microphoneEnabled {
                        FormRow(icon: "wand.and.stars", iconColor: .purple,
                                title: "自动检测", subtitle: "自动选择系统默认麦克风",
                                showSeparator: !recorder.autoSelectMic) {
                            Toggle("", isOn: $recorder.autoSelectMic).labelsHidden()
                        }

                        if !recorder.autoSelectMic {
                            ForEach(Array(recorder.audioDevices.enumerated()), id: \.element.id) { i, device in
                                let isMic = FFmpegHelper.isMicrophoneDevice(device.name)
                                let isSelected = device == recorder.selectedMicDevice
                                let isLast = i == recorder.audioDevices.count - 1

                                Button(action: { recorder.selectedMicDevice = device }) {
                                    FormRow(
                                        icon: isMic ? "mic.fill" : "speaker.wave.1",
                                        iconColor: isSelected ? .accentColor : .secondary,
                                        title: device.name,
                                        subtitle: isMic ? "麦克风" : "索引 \(device.index)",
                                        showSeparator: !isLast
                                    ) {
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                                .fontWeight(.semibold)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - 多输出设备配置提醒
// ────────────────────────────────────────────────────────────────────
struct MultiOutputSetupHint: View {
    let hasVirtualAudio: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: hasVirtualAudio ? "info.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(hasVirtualAudio ? .blue : .orange)
                    Text(hasVirtualAudio ? "请确认已配置「多输出设备」" : "需要安装虚拟音频驱动")
                        .font(.callout).fontWeight(.medium)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if hasVirtualAudio {
                        Text("录制系统声音时，若不配置多输出设备，你自己将听不到声音。")
                            .font(.caption).foregroundColor(.secondary)
                        stepList([
                            "打开「音频 MIDI 设置」（点击下方按钮）",
                            "点击左下角 ＋ → 创建「多输出设备」",
                            "勾选你的扬声器/耳机 + 虚拟音频设备",
                            "系统设置 → 声音 → 输出，选择该多输出设备",
                            "在本页设备列表中选择虚拟音频设备"
                        ])
                    } else {
                        Text("macOS 不支持直接录制系统声音，需安装虚拟音频驱动：")
                            .font(.caption).foregroundColor(.secondary)
                        stepList([
                            "安装 BlackHole: brew install blackhole-2ch",
                            "打开「音频 MIDI 设置」",
                            "创建「多输出设备」，勾选扬声器/耳机 + BlackHole",
                            "系统设置 → 声音 → 输出 → 选择该多输出设备",
                            "回到本应用，刷新设备列表"
                        ])
                    }

                    HStack(spacing: 10) {
                        Button(action: {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
                        }) {
                            Label("音频 MIDI 设置", systemImage: "pianokeys").font(.caption)
                        }
                        Button(action: {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Label("声音设置", systemImage: "speaker.wave.2").font(.caption)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hasVirtualAudio ? Color.blue.opacity(0.06) : Color.orange.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(hasVirtualAudio ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15), lineWidth: 1)
        )
    }

    private func stepList(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(i + 1)")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.accentColor))
                    Text(step).font(.caption)
                }
            }
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - 页面：视频
// ────────────────────────────────────────────────────────────────────
struct VideoPage: View {
    @EnvironmentObject var recorder: ScreenRecorderManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "视频", subtitle: "编码参数与画质设置")

            VStack(alignment: .leading, spacing: 6) {
                FormSectionLabel(title: "画质")
                FormCard {
                    Picker("", selection: $recorder.videoQuality) {
                        ForEach(VideoQuality.allCases) { q in Text(q.rawValue).tag(q) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(12)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                FormSectionLabel(title: "帧率")
                FormCard {
                    Picker("", selection: $recorder.frameRate) {
                        ForEach(FrameRate.allCases) { fps in Text(fps.displayText).tag(fps) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(12)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                FormSectionLabel(title: "编码信息")
                FormCard {
                    infoRow("编码器", "H.264 (libx264)", last: false)
                    infoRow("预设", "ultrafast（低延迟）", last: false)
                    infoRow("像素格式", "yuv420p", last: false)
                    infoRow("关键帧间隔", "60 帧", last: true)
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String, last: Bool) -> some View {
        FormRow(title: label, showSeparator: !last) {
            Text(value).foregroundColor(.secondary)
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - 页面：输出
// ────────────────────────────────────────────────────────────────────
struct OutputPage: View {
    @EnvironmentObject var recorder: ScreenRecorderManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "输出", subtitle: "文件格式和保存位置")

            VStack(alignment: .leading, spacing: 6) {
                FormSectionLabel(title: "格式")
                FormCard {
                    Picker("", selection: $recorder.outputFormat) {
                        if recorder.recordingMode == .audioOnly {
                            Text(OutputFormat.mp3.rawValue).tag(OutputFormat.mp3)
                            Text(OutputFormat.aac.rawValue).tag(OutputFormat.aac)
                        } else {
                            Text(OutputFormat.mp4.rawValue).tag(OutputFormat.mp4)
                            Text(OutputFormat.mov.rawValue).tag(OutputFormat.mov)
                            Text(OutputFormat.mkv.rawValue).tag(OutputFormat.mkv)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(12)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                FormSectionLabel(title: "保存位置")
                FormCard {
                    FormRow(icon: "folder.fill", iconColor: .accentColor, title: "保存路径", showSeparator: false) {
                        HStack(spacing: 6) {
                            Text(recorder.savePath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("选择...") { recorder.chooseSavePath() }
                                .font(.caption)
                        }
                    }
                }
            }

            if !recorder.outputPath.isEmpty && recorder.recordingState == .idle {
                VStack(alignment: .leading, spacing: 6) {
                    FormSectionLabel(title: "最近录制")
                    FormCard {
                        FormRow(icon: "doc.fill", iconColor: .orange,
                                title: (recorder.outputPath as NSString).lastPathComponent,
                                showSeparator: false) {
                            Button("在 Finder 中显示") { recorder.openOutputFile() }
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - 页面：日志
// ────────────────────────────────────────────────────────────────────
struct LogPage: View {
    @EnvironmentObject var recorder: ScreenRecorderManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "日志", subtitle: "FFmpeg 运行日志输出")

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(recorder.logMessages.enumerated()), id: \.offset) { index, msg in
                            Text(msg)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.green)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding(10)
                }
                .frame(maxWidth: .infinity, minHeight: 380)
                .background(Color.black.opacity(0.85))
                .cornerRadius(10)
                .onChange(of: recorder.logMessages.count) { _ in
                    if let last = recorder.logMessages.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            if recorder.logMessages.isEmpty {
                HStack {
                    Spacer()
                    Text("暂无日志，开始录制后将在此显示")
                        .font(.callout).foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }
}
