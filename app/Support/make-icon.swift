// Builds NoSpeaker's icon from the artwork in design/icon/ (made with Codex image generation): the artwork's
// body, measured from its alpha channel, is fitted to the macOS icon grid (an 824 px rounded square on 1024),
// over an opaque base, with the standard drop shadow, at every size macOS wants.
//
//   swift make-icon.swift <artwork.png> <out.iconset> [preview.png]
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let art = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("usage: make-icon <artwork.png> <out.iconset> [preview.png]"); exit(2)
}

/// The artwork's rounded-square body (top-left origin) and its colour. Generated artwork comes with a soft,
/// uneven shadow halo, so the body is found by colour, not transparency: its colour is read just inside the
/// top edge, then the edges are found by scanning in from the outside along the middle row and column.
func measure(_ image: CGImage) -> (body: CGRect, base: CGColor) {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let row = ctx.bytesPerRow
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: row * h)
    func rgba(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {     // memory row 0 is the top
        let i = y * row + x * 4
        return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]), Int(px[i + 3]))
    }
    // The body's colour: a little below the top edge, in the middle (above any artwork in the centre).
    var y0 = 0
    while y0 < h / 2 && rgba(w / 2, y0).3 < 250 { y0 += 1 }
    let body = rgba(w / 2, y0 + h / 16)
    func isBody(_ x: Int, _ y: Int) -> Bool {
        let c = rgba(x, y)
        return c.3 > 250 && abs(c.0 - body.0) + abs(c.1 - body.1) + abs(c.2 - body.2) < 110
    }
    var left = 0; while left < w / 2 && !isBody(left, h / 2) { left += 1 }
    var right = w - 1; while right > w / 2 && !isBody(right, h / 2) { right -= 1 }
    var top = 0; while top < h / 2 && !isBody(w / 2, top) { top += 1 }
    var bottom = h - 1; while bottom > h / 2 && !isBody(w / 2, bottom) { bottom -= 1 }
    let rect = CGRect(x: CGFloat(left), y: CGFloat(top), width: CGFloat(right - left + 1), height: CGFloat(bottom - top + 1))
    let base = CGColor(srgbRed: CGFloat(body.0) / 255, green: CGFloat(body.1) / 255, blue: CGFloat(body.2) / 255, alpha: 1)
    return (rect, base)
}

let (artBody, baseColour) = measure(art)
print("artwork body \(artBody)")

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    // Shadows ignore the scale above (they're in device pixels), so size this one to the icon.
    let k = CGFloat(pixels) / 1024
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(baseColour)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    // Inset the artwork's body a few pixels so its own soft edge stays outside the clip.
    let inner = artBody.insetBy(dx: artBody.width * 0.012, dy: artBody.height * 0.012)
    let sx = body.width / inner.width, sy = body.height / inner.height
    let w = CGFloat(art.width), h = CGFloat(art.height)
    ctx.draw(art, in: CGRect(x: body.minX - inner.minX * sx, y: body.minY - (h - inner.maxY) * sy, width: w * sx, height: h * sy))
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: args[2])
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(pixels: points * scale).representation(using: .png, properties: [:])!.write(to: iconset.appending(path: name))
    }
}
if args.count > 3 { try render(pixels: 512).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3])) }
print("drew \(iconset.path)")
