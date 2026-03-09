#!/bin/bash
set -e

# ============================================================
#  ScreenRecorder — 编译并打包为 DMG
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="ScreenRecorder"
BUNDLE_ID="com.screenrecorder.app"
VERSION="1.0.0"
BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION"
DMG_PATH="$DIST_DIR/$DMG_NAME.dmg"

echo "🔨 Step 1: 编译 Release 版本..."
cd "$PROJECT_DIR"
swift build -c release 2>&1
EXECUTABLE="$BUILD_DIR/$APP_NAME"

if [ ! -f "$EXECUTABLE" ]; then
    echo "❌ 编译失败: 找不到 $EXECUTABLE"
    exit 1
fi
echo "✅ 编译成功: $EXECUTABLE"

echo ""
echo "📦 Step 2: 创建 .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制可执行文件
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 创建 Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Screen Recorder</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Screen Recorder 需要屏幕录制权限来捕获屏幕内容</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Screen Recorder 需要麦克风权限来录制音频</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Screen Recorder 需要此权限来控制系统功能</string>
</dict>
</plist>
PLISTEOF
echo "✅ Info.plist 已创建"

# 创建 PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 生成应用图标 (使用系统自带的 sips 工具从 SF Symbols 风格生成)
echo ""
echo "🎨 Step 3: 生成应用图标..."
ICON_DIR="$DIST_DIR/AppIcon.iconset"
rm -rf "$ICON_DIR"
mkdir -p "$ICON_DIR"

# 使用 Python 生成一个简洁的录制图标
python3 << 'PYEOF'
import subprocess, os, sys

dist_dir = os.environ.get("DIST_DIR", "dist")
icon_dir = os.path.join(dist_dir, "AppIcon.iconset")

# 用 sips 从纯色 PNG 创建图标
# 先创建一个 1024x1024 的 base 图标
base_png = os.path.join(dist_dir, "icon_base.png")

# 使用 Python 的基本图形生成
try:
    # 尝试用 Pillow
    from PIL import Image, ImageDraw
    
    img = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # 圆角矩形背景
    draw.rounded_rectangle([40, 40, 984, 984], radius=180, fill=(220, 50, 50, 255))
    
    # 录制按钮 (白色圆形)
    draw.ellipse([280, 280, 744, 744], fill=(255, 255, 255, 255))
    
    # 内部红色圆形 (录制符号)
    draw.ellipse([380, 380, 644, 644], fill=(220, 50, 50, 255))
    
    img.save(base_png)
    print("  使用 Pillow 生成图标")
except ImportError:
    # 没有 Pillow, 使用 macOS 原生方法
    swift_code = '''
import AppKit
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

// 背景
let bgRect = NSRect(x: 40, y: 40, width: 944, height: 944)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 180, yRadius: 180)
NSColor(red: 0.86, green: 0.2, blue: 0.2, alpha: 1.0).setFill()
bgPath.fill()

// 白色圆
let whiteCircle = NSBezierPath(ovalIn: NSRect(x: 280, y: 280, width: 464, height: 464))
NSColor.white.setFill()
whiteCircle.fill()

// 红色内圆 (录制符号)
let redCircle = NSBezierPath(ovalIn: NSRect(x: 380, y: 380, width: 264, height: 264))
NSColor(red: 0.86, green: 0.2, blue: 0.2, alpha: 1.0).setFill()
redCircle.fill()

image.unlockFocus()

if let tiff = image.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: "''' + base_png.replace('"', '\\"') + '''"))
}
'''
    swift_file = os.path.join(dist_dir, "gen_icon.swift")
    with open(swift_file, 'w') as f:
        f.write(swift_code)
    subprocess.run(["swift", swift_file], check=True)
    os.remove(swift_file)
    print("  使用 Swift 生成图标")

if not os.path.exists(base_png):
    print("  ⚠️ 无法生成图标, 跳过")
    sys.exit(0)

# 生成各种尺寸
sizes = [16, 32, 64, 128, 256, 512, 1024]
for s in sizes:
    out = os.path.join(icon_dir, f"icon_{s}x{s}.png")
    subprocess.run(["sips", "-z", str(s), str(s), base_png, "--out", out],
                   capture_output=True)
    if s <= 512:
        out2x = os.path.join(icon_dir, f"icon_{s}x{s}@2x.png")
        s2 = s * 2
        subprocess.run(["sips", "-z", str(s2), str(s2), base_png, "--out", out2x],
                       capture_output=True)

os.remove(base_png)
print("  ✅ iconset 生成完毕")
PYEOF

# 转换 iconset -> icns
if [ -d "$ICON_DIR" ] && [ "$(ls -A "$ICON_DIR" 2>/dev/null)" ]; then
    iconutil -c icns "$ICON_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || echo "  ⚠️ iconutil 转换失败, 使用系统默认图标"
    rm -rf "$ICON_DIR"
    echo "✅ 应用图标已生成"
else
    echo "⚠️ 跳过图标生成, 使用系统默认图标"
fi

echo ""
echo "📀 Step 4: 创建 DMG..."
rm -f "$DMG_PATH"

# 创建临时目录作为 DMG 内容
DMG_TEMP="$DIST_DIR/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# 创建 Applications 快捷方式
ln -sf /Applications "$DMG_TEMP/Applications"

# 创建 DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH" 2>&1

rm -rf "$DMG_TEMP"

if [ -f "$DMG_PATH" ]; then
    DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
    echo ""
    echo "============================================================"
    echo "✅ 打包完成!"
    echo "============================================================"
    echo "  📦 App: $APP_BUNDLE"
    echo "  📀 DMG: $DMG_PATH"
    echo "  📊 大小: $DMG_SIZE"
    echo ""
    echo "  双击 DMG 文件, 将 $APP_NAME 拖入 Applications 即可安装"
    echo "============================================================"
else
    echo "❌ DMG 创建失败"
    exit 1
fi
