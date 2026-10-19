import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> NSColor { NSColor(white: white, alpha: alpha) }

// Background squircle on the macOS icon grid (824pt body inside 1024 canvas).
let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = gray(0, 0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
gray(0.1).setFill()
body.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [gray(0.22), gray(0.05)])!.draw(in: body, angle: -90)

// Book spines standing on a shelf; the last one leans on its neighbour.
let shelfY: CGFloat = 300
let spines: [(x: CGFloat, w: CGFloat, h: CGFloat, shade: CGFloat)] = [
    (262, 74, 380, 1.0), (346, 58, 330, 0.82), (414, 86, 420, 1.0), (510, 62, 300, 0.66), (582, 70, 360, 0.9),
]
for s in spines {
    gray(s.shade).setFill()
    NSBezierPath(roundedRect: NSRect(x: s.x, y: shelfY, width: s.w, height: s.h), xRadius: 14, yRadius: 14).fill()
    gray(0.05, 0.25).setFill()
    NSBezierPath(rect: NSRect(x: s.x + 12, y: shelfY + s.h - 70, width: s.w - 24, height: 10)).fill()
}
NSGraphicsContext.saveGraphicsState()
let lean = NSAffineTransform()
lean.translateX(by: 664, yBy: shelfY)
lean.rotate(byDegrees: -16)
lean.concat()
gray(0.75).setFill()
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 72, height: 340), xRadius: 14, yRadius: 14).fill()
NSGraphicsContext.restoreGraphicsState()

gray(1).setFill()
NSBezierPath(roundedRect: NSRect(x: 220, y: shelfY - 34, width: 584, height: 22), xRadius: 11, yRadius: 11).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
