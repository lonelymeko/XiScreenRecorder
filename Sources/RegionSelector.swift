import SwiftUI
import AppKit

/// 区域选择覆盖窗口
/// 使用独立的 NSPanel 避免阻塞主窗口事件循环
class RegionSelectionPanel: NSPanel {
    var onRegionSelected: ((CaptureRect) -> Void)?
    var onCancelled: (() -> Void)?
    
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var selectionView: RegionSelectionOverlay?
    
    convenience init(screen: NSScreen) {
        self.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.setFrame(screen.frame, display: true)
        self.level = .screenSaver  // 高层级确保在最前面
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let overlay = RegionSelectionOverlay(frame: screen.frame)
        self.contentView = overlay
        self.selectionView = overlay
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onCancelled?()
            orderOut(nil)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        startPoint = NSEvent.mouseLocation
        currentPoint = startPoint
        selectionView?.selectionRect = .zero
        selectionView?.needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        currentPoint = NSEvent.mouseLocation
        guard let current = currentPoint else { return }
        
        // 转换到窗口内坐标
        let screenFrame = self.frame
        let x1 = start.x - screenFrame.origin.x
        let y1 = start.y - screenFrame.origin.y
        let x2 = current.x - screenFrame.origin.x
        let y2 = current.y - screenFrame.origin.y
        
        let rect = NSRect(
            x: min(x1, x2),
            y: min(y1, y2),
            width: abs(x2 - x1),
            height: abs(y2 - y1)
        )
        
        selectionView?.selectionRect = rect
        selectionView?.needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint, let end = currentPoint else { return }
        
        let screenX = Int(min(start.x, end.x))
        let screenY = Int(min(start.y, end.y))
        let width = Int(abs(end.x - start.x))
        let height = Int(abs(end.y - start.y))
        
        orderOut(nil)
        
        if width > 10 && height > 10 {
            // 转换坐标系 (macOS y轴从底部, ffmpeg y轴从顶部)
            if let screen = NSScreen.main {
                let screenHeight = Int(screen.frame.height)
                let flippedY = screenHeight - screenY - height
                let rect = CaptureRect(x: screenX, y: flippedY, width: width, height: height)
                onRegionSelected?(rect.normalized)
            }
        } else {
            onCancelled?()
        }
    }
}

/// 区域选择覆盖视图
class RegionSelectionOverlay: NSView {
    var selectionRect: NSRect = .zero
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // 半透明覆盖
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()
        
        if selectionRect.width > 2 && selectionRect.height > 2 {
            // 选中区域清除半透明
            NSGraphicsContext.current?.compositingOperation = .clear
            selectionRect.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            
            // 选区边框
            NSColor.systemBlue.setStroke()
            let borderPath = NSBezierPath(rect: selectionRect)
            borderPath.lineWidth = 2
            borderPath.stroke()
            
            // 尺寸标签
            let sizeText = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.75)
            ]
            let textSize = sizeText.size(withAttributes: attrs)
            let textX = selectionRect.midX - textSize.width / 2
            let textY = selectionRect.maxY + 6
            sizeText.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
        } else {
            // 提示文字
            let text = "拖拽选择录制区域  ·  按 ESC 取消"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let size = text.size(withAttributes: attrs)
            let point = NSPoint(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2
            )
            text.draw(at: point, withAttributes: attrs)
        }
    }
    
    override var acceptsFirstResponder: Bool { true }
}

/// 区域选择器
class RegionSelector {
    private static var activePanel: RegionSelectionPanel?
    
    static func selectRegion(completion: @escaping (CaptureRect?) -> Void) {
        guard let screen = NSScreen.main else {
            completion(nil)
            return
        }
        
        let panel = RegionSelectionPanel(screen: screen)
        activePanel = panel  // 保持强引用
        
        panel.onRegionSelected = { rect in
            activePanel = nil
            completion(rect)
        }
        panel.onCancelled = {
            activePanel = nil
            completion(nil)
        }
        
        panel.makeKeyAndOrderFront(nil)
    }
}
