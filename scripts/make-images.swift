// Composes the README images from the app's own renders (NoSpeaker --snapshot) and the Codex-made wallpaper,
// optionally inside Apple's MacBook Pro bezel (a transparent-screen PNG from Apple Design Resources; not
// redistributed here). Without a bezel, the hero is the desktop itself, with a display's rounded corners.
//
//   swiftc -parse-as-library -O scripts/make-images.swift -o build/make-images
//   build/make-images <wallpaper.png> <snapshots folder> [bezel.png]
import AppKit

@main
struct MakeImages {
    static func main() throws {
        let a = CommandLine.arguments
        guard a.count == 3 || a.count == 4 else { print("usage: make-images <wallpaper.png> <snapshots folder> [bezel.png]"); exit(2) }
        let wallpaper = try load(a[1])
        let shots = URL(fileURLWithPath: a[2])
        func shot(_ name: String) throws -> CGImage { try load(shots.appending(path: name).path) }
        let music = window(try shot("1-music-light.png"))

        // Hero: the Music tab on the desktop, in the MacBook if there's a bezel with a transparent screen.
        if a.count == 4, case let bezel = try load(a[3]), case let cut = cutout(in: bezel), cut.width > 100 {
            print("bezel \(bezel.width)x\(bezel.height), screen \(cut)")
            let screen = desktop(size: cut.size, wallpaper: wallpaper, window: music)
            try save(scaled(compose(bezel: bezel, screen: screen, cut: cut), width: 2000), "docs/images/hero.png")
        } else {
            // A 16-inch MacBook Pro's desktop (1728 × 1117 pt at 2×), with its rounded corners and a soft shadow.
            let screen = desktop(size: CGSize(width: 3456, height: 2234), wallpaper: wallpaper, window: music)
            try save(scaled(display(screen), width: 2000), "docs/images/hero.png")
        }

        // Window shots for the README's sections, on a transparent background.
        for (file, out) in [("4-classics-light.png", "classics"), ("2-say-light.png", "say"), ("1-music-dark.png", "music-dark")] {
            try save(scaled(window(try shot(file)), width: 1400), "docs/images/\(out).png")
        }
        print("wrote docs/images/hero.png, classics.png, say.png, music-dark.png")
    }

    /// The app's render as a macOS window: rounded corners, the three window buttons, a hairline edge and a
    /// soft shadow, with room around it for the shadow.
    static func window(_ content: CGImage) -> CGImage {
        let w = CGFloat(content.width), h = CGFloat(content.height)
        let scale = w / 1120                     // the render is 1120 pt wide
        let pad = 90 * scale, radius = 16 * scale
        let ctx = context(Int(w + 2 * pad), Int(h + 2 * pad))
        let frame = CGRect(x: pad, y: pad, width: w, height: h)
        let shape = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -22 * scale), blur: 60 * scale, color: CGColor(gray: 0, alpha: 0.45))
        ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        ctx.interpolationQuality = .high
        ctx.draw(content, in: frame)
        // Close, minimise, zoom: 12 pt circles, 20 pt apart, 18 pt in from the top-left corner.
        for (i, rgb) in [(1.0, 0.373, 0.341), (0.996, 0.737, 0.18), (0.157, 0.784, 0.251)].enumerated() {
            let c = CGPoint(x: frame.minX + (19 + 20 * CGFloat(i)) * scale, y: frame.maxY - 19 * scale)
            let r = 6 * scale
            ctx.setFillColor(CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        ctx.restoreGState()
        ctx.addPath(CGPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.22)); ctx.setLineWidth(1); ctx.strokePath()
        return ctx.makeImage()!
    }

    /// The wallpaper, filled to the screen, with the window centred and scaled as it would be on a 16-inch
    /// MacBook Pro (1728 pt wide).
    static func desktop(size: CGSize, wallpaper: CGImage, window: CGImage) -> CGImage {
        let ctx = context(Int(size.width), Int(size.height))
        ctx.interpolationQuality = .high
        let ww = CGFloat(wallpaper.width), wh = CGFloat(wallpaper.height)
        let fill = max(size.width / ww, size.height / wh)
        ctx.draw(wallpaper, in: CGRect(x: (size.width - ww * fill) / 2, y: (size.height - wh * fill) / 2, width: ww * fill, height: wh * fill))
        let pointsToPixels = size.width / 1728
        let s = pointsToPixels / (CGFloat(window.width) / (1120 + 180))   // the window image is 1120 pt + 2 × 90 pt padding
        let w = CGFloat(window.width) * s, h = CGFloat(window.height) * s
        ctx.draw(window, in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2 - 10 * pointsToPixels, width: w, height: h))
        return ctx.makeImage()!
    }

    /// The desktop as a display: rounded corners, a hairline edge and a soft shadow, on transparent.
    static func display(_ screen: CGImage) -> CGImage {
        let w = CGFloat(screen.width), h = CGFloat(screen.height)
        let pad = w * 0.04, radius = w * 0.012
        let ctx = context(Int(w + 2 * pad), Int(h + 2 * pad))
        let frame = CGRect(x: pad, y: pad, width: w, height: h)
        let shape = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -w * 0.008), blur: w * 0.025, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState(); ctx.addPath(shape); ctx.clip(); ctx.draw(screen, in: frame); ctx.restoreGState()
        return ctx.makeImage()!
    }

    // MARK: - Helpers (from Fillet's make-images.swift)

    static func load(_ path: String) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw NSError(domain: "make-images", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot read \(path)"]) }
        return img
    }

    static func context(_ w: Int, _ h: Int) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// The transparent screen area of the bezel, in top-left-origin pixel coordinates.
    static func cutout(in bezel: CGImage) -> CGRect {
        let w = bezel.width, h = bezel.height
        let ctx = context(w, h)
        ctx.draw(bezel, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = ctx.data!.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * h)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { px[y * ctx.bytesPerRow + x * 4 + 3] }
        let cy = h / 2, cx = w / 2
        var l = cx; while l > 0 && alpha(l - 1, cy) < 128 { l -= 1 }
        var r = cx; while r < w - 1 && alpha(r + 1, cy) < 128 { r += 1 }
        let qx = l + (r - l) / 6
        var t = cy; while t > 0 && alpha(qx, t - 1) < 128 { t -= 1 }
        var b = cy; while b < h - 1 && alpha(qx, b + 1) < 128 { b += 1 }
        return CGRect(x: l, y: t, width: r - l + 1, height: b - t + 1)
    }

    static func compose(bezel: CGImage, screen: CGImage, cut: CGRect) -> CGImage {
        let w = bezel.width, h = bezel.height
        let ctx = context(w, h)
        ctx.draw(screen, in: CGRect(x: cut.minX, y: CGFloat(h) - cut.maxY, width: cut.width, height: cut.height))
        ctx.draw(bezel, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    static func scaled(_ image: CGImage, width: Int) -> CGImage {
        let height = Int(Double(image.height) * Double(width) / Double(image.width))
        let ctx = context(width, height)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    static func save(_ image: CGImage, _ path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
