// Generates assets/AppIcon.png (1024x1024). Run via tools/make-icon.sh
import AppKit

let size = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

// soft drop shadow
let sh = NSShadow()
sh.shadowColor = NSColor.black.withAlphaComponent(0.35)
sh.shadowBlurRadius = 28
sh.shadowOffset = NSSize(width: 0, height: -14)
NSGraphicsContext.saveGraphicsState()
sh.set()
NSColor.black.setFill()
path.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.83, blue: 0.78, alpha: 1),
                    NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.86, alpha: 1)])!.draw(in: path, angle: -60)

let s = "🧹" as NSString
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont(name: "AppleColorEmoji", size: 520) ?? NSFont.systemFont(ofSize: 520)]
let sz = s.size(withAttributes: attrs)
s.draw(at: NSPoint(x: 512 - sz.width / 2, y: 512 - sz.height / 2), withAttributes: attrs)

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
