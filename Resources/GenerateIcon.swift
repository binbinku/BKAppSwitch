import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = NSBezierPath(roundedRect: NSRect(x: 66, y: 66, width: 892, height: 892), xRadius: 202, yRadius: 202)
        NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.25, alpha: 1),
                   ending: NSColor(calibratedRed: 0.035, green: 0.08, blue: 0.12, alpha: 1))!.draw(in: background, angle: -60)
        NSColor(calibratedWhite: 1, alpha: 0.13).setStroke()
        background.lineWidth = 3
        background.stroke()
        let back = NSBezierPath(roundedRect: NSRect(x: 260, y: 370, width: 490, height: 330), xRadius: 45, yRadius: 45)
        NSColor(calibratedRed: 0.24, green: 0.54, blue: 0.55, alpha: 1).setFill()
        back.fill()
        let front = NSBezierPath(roundedRect: NSRect(x: 205, y: 290, width: 490, height: 330), xRadius: 45, yRadius: 45)
        NSColor(calibratedRed: 0.30, green: 0.86, blue: 0.74, alpha: 1).setFill()
        front.fill()
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 337, y: 455))
        arrow.line(to: NSPoint(x: 553, y: 455))
        arrow.move(to: NSPoint(x: 483, y: 525))
        arrow.line(to: NSPoint(x: 553, y: 455))
        arrow.line(to: NSPoint(x: 483, y: 385))
        NSColor(calibratedRed: 0.04, green: 0.17, blue: 0.20, alpha: 1).setStroke()
        arrow.lineWidth = 29
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.stroke()
        image.unlockFocus()
        let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: destination.appendingPathComponent(name))
    }
}
