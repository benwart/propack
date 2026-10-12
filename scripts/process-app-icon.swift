import Cocoa
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 3 else {
    print("Usage: process-app-icon <input.jpg> <output.png>")
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

guard let image = NSImage(contentsOfFile: inputPath) else {
    print("Failed to load input image: \(inputPath)")
    exit(1)
}

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let cgImage = bitmap.cgImage else {
    print("Failed to get CGImage from input image")
    exit(1)
}

let width = cgImage.width
let height = cgImage.height

guard let inData = cgImage.dataProvider?.data,
      let ptr = CFDataGetBytePtr(inData) else {
    print("Failed to get pixel data")
    exit(1)
}

// In the bitmap buffer (top-left origin, y = 0 is top):
var minX = width
var maxX = 0
var minY = height
var maxY = 0

// Find pixels that belong to the squircle (orange/amber gradient)
for y in 0..<height {
    for x in 0..<width {
        let offset = (y * width + x) * 4
        let r = Int(ptr[offset])
        let g = Int(ptr[offset + 1])
        let b = Int(ptr[offset + 2])
        let isOrange = (r > 170 && b < 130 && (r - b) > 60) || (r > 190 && g > 70 && b < 150)
        if isOrange {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
}

print("Detected source squircle bounding box: x: \(minX)...\(maxX), y: \(minY)...\(maxY)")
let srcSquircleW = CGFloat(maxX - minX + 1)
let srcSquircleH = CGFloat(maxY - minY + 1)

// In CGContext coordinates (origin bottom-left, y = 0 at bottom):
let srcCGX = CGFloat(minX)
let srcCGY = CGFloat(height) - CGFloat(maxY + 1)
let srcSquircleRect = CGRect(x: srcCGX, y: srcCGY, width: srcSquircleW, height: srcSquircleH)

// 1. First, create an image of just the clipped squircle (at original resolution)
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let squircleCtx = CGContext(
    data: nil,
    width: Int(srcSquircleW),
    height: Int(srcSquircleH),
    bitsPerComponent: 8,
    bytesPerRow: 4 * Int(srcSquircleW),
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("Failed to create squircle CGContext")
    exit(1)
}

let squircleLocalRect = CGRect(x: 0, y: 0, width: srcSquircleW, height: srcSquircleH)
let srcCornerRadius = srcSquircleW * 0.2237
let squirclePath = CGPath(roundedRect: squircleLocalRect, cornerWidth: srcCornerRadius, cornerHeight: srcCornerRadius, transform: nil)

squircleCtx.addPath(squirclePath)
squircleCtx.clip()

// Draw the source image shifted so the squircle lines up with (0,0)
squircleCtx.draw(cgImage, in: CGRect(x: -srcCGX, y: -srcCGY, width: CGFloat(width), height: CGFloat(height)))

guard let clippedSquircleCG = squircleCtx.makeImage() else {
    print("Failed to extract clipped squircle")
    exit(1)
}

// 2. Now render onto standard macOS 1024x1024 icon canvas with standard 824x824 size and macOS drop shadow
let targetCanvasSize: CGFloat = 1024
guard let canvasCtx = CGContext(
    data: nil,
    width: Int(targetCanvasSize),
    height: Int(targetCanvasSize),
    bitsPerComponent: 8,
    bytesPerRow: 4 * Int(targetCanvasSize),
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("Failed to create canvas CGContext")
    exit(1)
}

canvasCtx.clear(CGRect(x: 0, y: 0, width: targetCanvasSize, height: targetCanvasSize))

// Apple macOS Big Sur icon grid: standard squircle is 824x824 centered
let targetSquircleSize: CGFloat = 824
let targetX = (targetCanvasSize - targetSquircleSize) / 2.0 // 100.0
let targetY = (targetCanvasSize - targetSquircleSize) / 2.0 // 100.0
let targetSquircleRect = CGRect(x: targetX, y: targetY, width: targetSquircleSize, height: targetSquircleSize)
let targetCornerRadius = targetSquircleSize * 0.2237 // ~184.3

// Draw standard macOS soft drop shadow beneath the squircle
canvasCtx.saveGState()
let shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.28)
canvasCtx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: shadowColor)

let targetPath = CGPath(roundedRect: targetSquircleRect, cornerWidth: targetCornerRadius, cornerHeight: targetCornerRadius, transform: nil)
canvasCtx.addPath(targetPath)
canvasCtx.setFillColor(CGColor(red: 0.9, green: 0.45, blue: 0.1, alpha: 1.0))
canvasCtx.fillPath()
canvasCtx.restoreGState()

// Draw the clipped squircle content inside the target squircle rect
canvasCtx.saveGState()
canvasCtx.addPath(targetPath)
canvasCtx.clip()
canvasCtx.draw(clippedSquircleCG, in: targetSquircleRect)
canvasCtx.restoreGState()

guard let finalCGImage = canvasCtx.makeImage() else {
    print("Failed to produce final canvas image")
    exit(1)
}

let outRep = NSBitmapImageRep(cgImage: finalCGImage)
guard let pngData = outRep.representation(using: .png, properties: [:]) else {
    print("Failed to create PNG representation")
    exit(1)
}

try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Successfully generated macOS-compliant 1024x1024 icon at: \(outputPath)")
