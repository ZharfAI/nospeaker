// Draws NoSpeaker's icon at every size macOS wants: ink on paper, a trackpad with a sound wave running
// through it. Usage: swift make-icon.swift <folder.iconset>
import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "NoSpeaker.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

func draw(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    let s = CGFloat(pixels) / 1024
    cg.scaleBy(x: s, y: s)

    let paper = CGColor(srgbRed: 246 / 255, green: 245 / 255, blue: 241 / 255, alpha: 1)
    let ink = CGColor(srgbRed: 12 / 255, green: 12 / 255, blue: 12 / 255, alpha: 1)

    // The body: Apple's icon grid (824 pt on 1024), with a soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.28))
    cg.addPath(CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil))
    cg.setFillColor(paper)
    cg.fillPath()
    cg.restoreGState()

    // The trackpad.
    let pad = CGRect(x: 192, y: 322, width: 640, height: 380)
    cg.addPath(CGPath(roundedRect: pad, cornerWidth: 52, cornerHeight: 52, transform: nil))
    cg.setStrokeColor(ink)
    cg.setLineWidth(22)
    cg.strokePath()

    // The sound running through it: a wave that grows toward the middle and fades out.
    let wave = CGMutablePath()
    let left = pad.minX + 58, right = pad.maxX - 58, mid = pad.midY
    for i in 0...400 {
        let u = CGFloat(i) / 400
        let x = left + (right - left) * u
        let envelope = sin(.pi * u)
        let y = mid + 108 * envelope * sin(2 * .pi * 4.5 * u)
        if i == 0 { wave.move(to: CGPoint(x: x, y: y)) } else { wave.addLine(to: CGPoint(x: x, y: y)) }
    }
    cg.addPath(wave)
    cg.setLineWidth(26)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, pixels) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                       ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try draw(pixels: pixels).write(to: folder.appending(path: "icon_\(name).png"))
}
print("drew \(folder.path)")
