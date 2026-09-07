// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit

// Render at both scale factors; dmgbuild combines them into a Finder HiDPI TIFF.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let artwork = NSImage(contentsOfFile: CommandLine.arguments[2])!
let version = CommandLine.arguments[3]
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let width: CGFloat = 720, height: CGFloat = 530
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x, y: height-y-h, width: w, height: h) }
func rounded(_ rect: NSRect, _ radius: CGFloat, _ fill: NSColor) {
  fill.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func label(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, foreground: NSColor = color(0x213B31), tracking: CGFloat = 0) {
  let style = NSMutableParagraphStyle(); style.lineBreakMode = .byClipping
  (value as NSString).draw(in: box(x, y, width, size * 1.7), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: foreground, .kern: tracking, .paragraphStyle: style])
}
for scale in [1, 2] {
  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width)*scale, pixelsHigh: Int(height)*scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  bitmap.size = NSSize(width: width, height: height)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  NSGradient(colors: [color(0xF5F8F5), color(0xEAF2ED)])!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -40)
  rounded(box(44, 37, 24, 24), 8, color(0x1C8B60, 0.10))
  let mouse = NSBezierPath(roundedRect: box(52, 42, 9, 14), xRadius: 4, yRadius: 4)
  color(0x278760).setStroke(); mouse.lineWidth = 1.4; mouse.stroke()
  let wheel = NSBezierPath(); wheel.move(to: NSPoint(x: 56.5, y: height-45)); wheel.line(to: NSPoint(x: 56.5,y:height-49)); wheel.lineWidth=1.3; wheel.stroke()
  label("RAZER MOUSE", x: 80, y: 40, width: 240, size: 11, weight: .semibold, tracking: 2.2)
  rounded(box(530, 36, 146, 27), 13.5, color(0xFFFFFF, 0.65))
  label("为 macOS 而设计", x: 551, y: 42, width: 130, size: 11, foreground: color(0x668176))
  label("让操控，回归直觉。", x: 44, y: 87, width: 550, size: 30, weight: .semibold, tracking: 0.2)
  label("将左侧应用拖入右侧文件夹，即可安装。", x: 45, y: 133, width: 550, size: 14, foreground: color(0x718278))
  artwork.draw(in: box(604, 90, 44, 64), from: .zero, operation: .sourceOver, fraction: 0.35)
  for x: CGFloat in [110,430] {
    rounded(box(x, 189, 180, 174), 29, color(0xFFFFFF, 0.66))
    color(0xBFD8CA, 0.42).setStroke()
    let edge=NSBezierPath(roundedRect:box(x+0.5,189.5,179,173),xRadius:28.5,yRadius:28.5);edge.lineWidth=1;edge.stroke()
  }
  let arrow=NSBezierPath(); arrow.move(to:NSPoint(x:330,y:height-265));arrow.line(to:NSPoint(x:390,y:height-265));arrow.move(to:NSPoint(x:379,y:height-254));arrow.line(to:NSPoint(x:390,y:height-265));arrow.line(to:NSPoint(x:379,y:height-276));arrow.lineWidth=2.2;arrow.lineCapStyle = .round;arrow.lineJoinStyle = .round;color(0x479E79).setStroke();arrow.stroke()
  label("拖拽安装", x: 334, y: 287, width: 85, size: 11, foreground:color(0x799185))
  rounded(box(44, 393, 632, 65), 18, color(0xFFFFFF,0.65))
  rounded(box(61, 410, 30, 30), 10, color(0x25865E,0.09))
  if let icon=NSImage(systemSymbolName:"hand.raised", accessibilityDescription:nil) {
    icon.isTemplate=false; icon.draw(in:box(69,417,14,16),from:.zero,operation:.sourceOver,fraction:0.60)
  }
  label("首次打开，按提示允许「输入监控」", x: 104, y: 404, width: 545, size: 13, weight:.medium)
  label("安装后，从菜单栏查看电量、调整鼠标设置。", x:104,y:428,width:545,size:11,foreground:color(0x7C8A82))
  label("RazerMouse  ·  \(version)", x:44,y:475,width:290,size:10,foreground:color(0x84928A))
  label("Apple Silicon  /  macOS 14+",x:532,y:475,width:180,size:10,foreground:color(0x84928A))
  NSGraphicsContext.restoreGraphicsState()
  let name = scale == 1 ? "background.png" : "background@2x.png"
  try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name))
}
