import Foundation

/// 录制模式
enum RecordingMode: String, CaseIterable, Identifiable {
    case screenOnly = "仅屏幕"
    case screenAndAudio = "屏幕 + 系统声音"
    case audioOnly = "仅系统音频"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .screenOnly: return "rectangle.dashed.and.arrow.up"
        case .screenAndAudio: return "rectangle.and.text.magnifyingglass"
        case .audioOnly: return "speaker.wave.3"
        }
    }
    
    var description: String {
        switch self {
        case .screenOnly: return "只录制屏幕画面，不录制声音"
        case .screenAndAudio: return "同时录制屏幕画面和系统声音"
        case .audioOnly: return "只录制系统音频，输出音频文件"
        }
    }
}

/// 屏幕区域选择方式
enum CaptureArea: String, CaseIterable, Identifiable {
    case fullScreen = "全屏"
    case custom = "自定义区域"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .fullScreen: return "rectangle.fill"
        case .custom: return "rectangle.dashed"
        }
    }
}

/// 录制状态
enum RecordingState: Equatable {
    case idle
    case recording
    case paused
    
    var displayText: String {
        switch self {
        case .idle: return "就绪"
        case .recording: return "录制中"
        case .paused: return "已暂停"
        }
    }
}

/// 视频质量预设
enum VideoQuality: String, CaseIterable, Identifiable {
    case low = "低 (720p)"
    case medium = "中 (1080p)"
    case high = "高 (原始分辨率)"
    
    var id: String { rawValue }
    
    var crf: String {
        switch self {
        case .low: return "28"
        case .medium: return "23"
        case .high: return "18"
        }
    }
}

/// 视频帧率
enum FrameRate: Int, CaseIterable, Identifiable {
    case fps15 = 15
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60
    
    var id: Int { rawValue }
    
    var displayText: String {
        return "\(rawValue) FPS"
    }
}

/// 输出格式
enum OutputFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4"
    case mov = "MOV"
    case mkv = "MKV"
    case mp3 = "MP3 (仅音频)"
    case aac = "AAC (仅音频)"
    
    var id: String { rawValue }
    
    var fileExtension: String {
        switch self {
        case .mp4: return "mp4"
        case .mov: return "mov"
        case .mkv: return "mkv"
        case .mp3: return "mp3"
        case .aac: return "aac"
        }
    }
    
    var isAudioOnly: Bool {
        return self == .mp3 || self == .aac
    }
    
    var isVideoFormat: Bool {
        return !isAudioOnly
    }
}

/// 自定义录制区域
struct CaptureRect: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    
    static let zero = CaptureRect(x: 0, y: 0, width: 0, height: 0)
    
    var isValid: Bool {
        return width > 0 && height > 0
    }
    
    /// 确保宽高为偶数（ffmpeg要求）
    var normalized: CaptureRect {
        var w = width
        var h = height
        if w % 2 != 0 { w += 1 }
        if h % 2 != 0 { h += 1 }
        return CaptureRect(x: x, y: y, width: w, height: h)
    }
}
