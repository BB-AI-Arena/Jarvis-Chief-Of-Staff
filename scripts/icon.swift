import AppKit
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 20, y: 20, width: 984, height: 984), xRadius: 220, yRadius: 220)
NSColor(calibratedRed: 0.02, green: 0.055, blue: 0.105, alpha: 1).setFill(); background.fill()
let colors = [NSColor(calibratedRed: 0.05, green: 0.38, blue: 0.57, alpha: 1), NSColor(calibratedRed: 0.02, green: 0.12, blue: 0.27, alpha: 1), NSColor(calibratedRed: 0.27, green: 0.82, blue: 0.97, alpha: 1)]
let circle = NSBezierPath(ovalIn: NSRect(x: 200, y: 200, width: 624, height: 624))
NSGradient(colors: colors)!.draw(in: circle, relativeCenterPosition: NSPoint(x: -0.25, y: 0.4))
let shadow = NSShadow(); shadow.shadowColor = NSColor.cyan.withAlphaComponent(0.6); shadow.shadowBlurRadius = 40; shadow.set()
NSColor(calibratedRed: 0.4, green: 0.88, blue: 1, alpha: 0.85).setStroke(); circle.lineWidth = 4; circle.stroke()
for i in 0..<14 {
    let path = NSBezierPath()
    for step in 0...180 {
        let a = Double(step) / 180 * .pi * 2
        let b = Double(i) / 14 * .pi
        let x = 512 + cos(a) * 304
        let y = 512 + sin(a) * cos(b) * 304
        if step == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
    }
    NSColor(calibratedRed: 0.6, green: 0.93, blue: 1, alpha: 0.24).setStroke(); path.lineWidth = 2; path.stroke()
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
