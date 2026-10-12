import AppKit
import Foundation

let ptWidth: CGFloat = 660
let ptHeight: CGFloat = 400

func render(scale: CGFloat, logoURL: URL) -> NSBitmapImageRep {
    let pxWidth = Int(ptWidth * scale)
    let pxHeight = Int(ptHeight * scale)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pxWidth,
        pixelsHigh: pxHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: pxWidth * 4,
        bitsPerPixel: 32
    ) else {
        fatalError("Failed to allocate bitmap rep")
    }

    rep.size = NSSize(width: ptWidth, height: ptHeight)

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Failed to create graphics context")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }

    let ctx = graphicsContext.cgContext

    // Coordinates: AppKit native has (0, 0) at bottom-left.
    // Let's define helper to convert top-down Y (0 at top, 400 at bottom) to AppKit Y.
    func topY(_ y: CGFloat) -> CGFloat {
        return ptHeight - y
    }

    // 1. Draw rich gradient background (Amber-Gold to Warm Coral)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let startColor = CGColor(red: 255/255, green: 178/255, blue: 50/255, alpha: 1.0) // Warm Amber
    let midColor   = CGColor(red: 255/255, green: 138/255, blue: 38/255, alpha: 1.0) // Rich Orange
    let endColor   = CGColor(red: 232/255, green: 72/255, blue: 44/255, alpha: 1.0)  // Warm Coral
    let colors = [startColor, midColor, endColor] as CFArray
    let locations: [CGFloat] = [0.0, 0.45, 1.0]

    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else {
        fatalError("Failed to create CGGradient")
    }

    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: ptHeight), // AppKit top-left
        end: CGPoint(x: ptWidth, y: 0),    // AppKit bottom-right
        options: []
    )

    // 2. Subtle soft pedestal glow behind the two icon slots (x: 180, x: 480, y: 205 from top)
    let leftGlowCenter = CGPoint(x: 180, y: topY(205))
    let rightGlowCenter = CGPoint(x: 480, y: topY(205))

    let glowColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.18),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
    ] as CFArray
    if let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(glowGradient, startCenter: leftGlowCenter, startRadius: 0, endCenter: leftGlowCenter, endRadius: 90, options: [])
        ctx.drawRadialGradient(glowGradient, startCenter: rightGlowCenter, startRadius: 0, endCenter: rightGlowCenter, endRadius: 90, options: [])
    }

    // Subtle drop shadow for text & graphics
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -2)
    shadow.shadowBlurRadius = 4

    // 3. Logo at Top Center (x: 330, y: 22 from top, size: 50x50)
    if let logoImage = NSImage(contentsOf: logoURL) {
        let logoSize: CGFloat = 50
        let logoRect = NSRect(
            x: 330 - (logoSize / 2),
            y: topY(22 + logoSize),
            width: logoSize,
            height: logoSize
        )

        // Draw shadow under logo
        ctx.saveGState()
        let logoShadow = NSShadow()
        logoShadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        logoShadow.shadowOffset = NSSize(width: 0, height: -3)
        logoShadow.shadowBlurRadius = 8
        logoShadow.set()

        // Clip rounded squircle for logo
        let squirclePath = NSBezierPath(roundedRect: logoRect, xRadius: 11, yRadius: 11)
        squirclePath.addClip()
        logoImage.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        ctx.restoreGState()

        // Border around logo
        let borderPath = NSBezierPath(roundedRect: logoRect, xRadius: 11, yRadius: 11)
        borderPath.lineWidth = 1.0
        NSColor.white.withAlphaComponent(0.35).setStroke()
        borderPath.stroke()
    }

    // 4. Header Text
    let title = "ProPack"
    let titleFont = NSFont.systemFont(ofSize: 21, weight: .bold)
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor.white,
        .shadow: shadow
    ]
    let titleSize = (title as NSString).size(withAttributes: titleAttrs)
    let titleRect = NSRect(
        x: (ptWidth - titleSize.width) / 2,
        y: topY(78 + titleSize.height),
        width: titleSize.width,
        height: titleSize.height
    )
    (title as NSString).draw(in: titleRect, withAttributes: titleAttrs)

    let subtitle = "Drag ProPack to Applications to install"
    let subtitleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    let subtitleAttrs: [NSAttributedString.Key: Any] = [
        .font: subtitleFont,
        .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        .shadow: shadow
    ]
    let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttrs)
    let subtitleRect = NSRect(
        x: (ptWidth - subtitleSize.width) / 2,
        y: topY(104 + subtitleSize.height),
        width: subtitleSize.width,
        height: subtitleSize.height
    )
    (subtitle as NSString).draw(in: subtitleRect, withAttributes: subtitleAttrs)

    // 5. Drag-and-Drop Installation Arrow between Left (180) and Right (480)
    let arrowCenterY = topY(205)
    let arrowPillRect = NSRect(x: 330 - 44, y: arrowCenterY - 16, width: 88, height: 32)

    // Pill background
    ctx.saveGState()
    let pillShadow = NSShadow()
    pillShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    pillShadow.shadowOffset = NSSize(width: 0, height: -2)
    pillShadow.shadowBlurRadius = 4
    pillShadow.set()

    let pillPath = NSBezierPath(roundedRect: arrowPillRect, xRadius: 16, yRadius: 16)
    NSColor.white.withAlphaComponent(0.24).setFill()
    pillPath.fill()
    NSColor.white.withAlphaComponent(0.40).setStroke()
    pillPath.lineWidth = 1.0
    pillPath.stroke()
    ctx.restoreGState()

    // Right-pointing arrow shape inside pill
    let arrowPath = NSBezierPath()
    let arrowStartX: CGFloat = 330 - 18
    let arrowEndX: CGFloat = 330 + 16
    let shaftY: CGFloat = arrowCenterY
    let arrowHeadSize: CGFloat = 7

    // Shaft
    arrowPath.move(to: NSPoint(x: arrowStartX, y: shaftY))
    arrowPath.line(to: NSPoint(x: arrowEndX, y: shaftY))

    // Arrowhead
    arrowPath.line(to: NSPoint(x: arrowEndX - arrowHeadSize, y: shaftY + arrowHeadSize))
    arrowPath.move(to: NSPoint(x: arrowEndX, y: shaftY))
    arrowPath.line(to: NSPoint(x: arrowEndX - arrowHeadSize, y: shaftY - arrowHeadSize))

    arrowPath.lineWidth = 3.2
    arrowPath.lineCapStyle = .round
    arrowPath.lineJoinStyle = .round
    NSColor.white.withAlphaComponent(0.95).setStroke()
    arrowPath.stroke()

    // 6. Subtle Footer Label at bottom
    let footer = "macOS 14.0 or later"
    let footerFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    let footerAttrs: [NSAttributedString.Key: Any] = [
        .font: footerFont,
        .foregroundColor: NSColor.white.withAlphaComponent(0.65)
    ]
    let footerSize = (footer as NSString).size(withAttributes: footerAttrs)
    let footerRect = NSRect(
        x: (ptWidth - footerSize.width) / 2,
        y: topY(375 + footerSize.height),
        width: footerSize.width,
        height: footerSize.height
    )
    (footer as NSString).draw(in: footerRect, withAttributes: footerAttrs)

    return rep
}

let projectDir = FileManager.default.currentDirectoryPath
let logoURL = URL(fileURLWithPath: "\(projectDir)/docs/assets/logo.png")
let configDir = URL(fileURLWithPath: "\(projectDir)/Config")

print("==> Rendering 1x background (660x400 @ 72 DPI)...")
let rep1x = render(scale: 1.0, logoURL: logoURL)
let data1x = rep1x.representation(using: .png, properties: [:])!
let out1xURL = configDir.appending(path: "dmg-background.png")
try data1x.write(to: out1xURL)

print("==> Rendering 2x background (1320x800 @ 144 DPI)...")
let rep2x = render(scale: 2.0, logoURL: logoURL)
let data2x = rep2x.representation(using: .png, properties: [:])!
let out2xURL = configDir.appending(path: "dmg-background@2x.png")
try data2x.write(to: out2xURL)

print("==> Setting DPI metadata using sips...")
let sips1 = Process()
sips1.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
sips1.arguments = ["-s", "dpiWidth", "72", "-s", "dpiHeight", "72", out1xURL.path]
try sips1.run()
sips1.waitUntilExit()

let sips2 = Process()
sips2.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
sips2.arguments = ["-s", "dpiWidth", "144", "-s", "dpiHeight", "144", out2xURL.path]
try sips2.run()
sips2.waitUntilExit()

print("==> Combining into Retina multi-resolution TIFF via tiffutil...")
let tiffURL = configDir.appending(path: "dmg-background.tiff")
let tiffProc = Process()
tiffProc.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffProc.arguments = ["-cathidpicheck", out1xURL.path, out2xURL.path, "-out", tiffURL.path]
try tiffProc.run()
tiffProc.waitUntilExit()

print("==> DMG background created successfully:")
print("    1x: \(out1xURL.path)")
print("    2x: \(out2xURL.path)")
print("  TIFF: \(tiffURL.path)")
