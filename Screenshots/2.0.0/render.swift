// Renders App Store screenshots: background, caption, device frame, screenshot.
// Usage: swift render.swift <captions.json> <shots dir> <out dir>
// captions.json: {"rtl": false, "slides": [["1-learn", "Learn *Greek*.", "A few minutes a day."], ...]}
// Each slide: source file name (without .png) in <shots dir>, title, subtitle. A name starting with "ipad" is an iPad slide.
import AppKit

let a = CommandLine.arguments
let cfg = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: a[1]))) as! [String: Any]
let slides = cfg["slides"] as! [[String]]
let rtl = cfg["rtl"] as? Bool ?? false
let shots = a[2], out = a[3]

func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
let bg = hex(0xE8F1FB), deep = hex(0x1A3A5C), accent = hex(0x2D7FF9), slate = hex(0x5A6978)

// "Learn *Greek*." -> attributed string with the starred word in accent blue
func styled(_ s: String, font: NSFont, color: NSColor) -> NSAttributedString {
    let p = NSMutableParagraphStyle()
    p.alignment = .center
    p.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
    p.lineHeightMultiple = 0.95
    let r = NSMutableAttributedString()
    for (i, part) in s.components(separatedBy: "*").enumerated() {
        r.append(NSAttributedString(string: part, attributes: [.font: font, .foregroundColor: i % 2 == 1 ? accent : color, .paragraphStyle: p]))
    }
    return r
}

func render(_ i: Int) {
    let file = slides[i][0]
    let iPad = file.hasPrefix("ipad")
    let (W, H): (CGFloat, CGFloat) = iPad ? (2048, 2732) : (1206, 2622)
    // No alpha channel: App Store Connect rejects screenshots with one
    let cg = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    cg.translateBy(x: 0, y: H); cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    bg.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()

    // Caption block
    let margin: CGFloat = iPad ? 160 : 70
    let textW = W - 2 * margin
    // The device sits at the same height on every slide; a long caption shrinks to fit above it.
    let top: CGFloat = iPad ? 760 : 580
    var scale: CGFloat = 1
    var blocks: [(NSAttributedString, CGFloat, CGFloat)] = []
    while true {
        let title = styled(slides[i][1], font: .systemFont(ofSize: (iPad ? 150 : 104) * scale, weight: .semibold), color: deep)
        let sub = styled(slides[i][2], font: .systemFont(ofSize: (iPad ? 96 : 64) * scale, weight: .regular), color: slate)
        blocks = [(title, CGFloat(iPad ? 40 : 28) * scale, 0), (sub, 0, 0)].map { s, gap, _ in
            (s, gap, ceil(s.boundingRect(with: NSSize(width: textW, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height))
        }
        if blocks.reduce(0, { $0 + $1.1 + $1.2 }) <= top - (iPad ? 240 : 190) || scale < 0.6 { break }
        scale -= 0.05
    }
    var y: CGFloat = iPad ? 150 : 120
    for (s, gap, h) in blocks {
        s.draw(with: NSRect(x: margin, y: y, width: textW, height: h), options: [.usesLineFragmentOrigin, .usesFontLeading])
        y += h + gap
    }

    // Device: black body, screen inset by the bezel, cut off at the bottom like the 1.4.0 set
    let shot = NSImage(contentsOfFile: "\(shots)/\(file).png")!
    let bezel: CGFloat = iPad ? 46 : 30
    let screenW: CGFloat = iPad ? 1640 : min(860, (H - top - 70 - 2 * bezel) / (shot.size.height / shot.size.width))
    let screenH = screenW * shot.size.height / shot.size.width
    let body = NSRect(x: (W - screenW) / 2 - bezel, y: top, width: screenW + 2 * bezel, height: screenH + 2 * bezel)
    let bodyR: CGFloat = iPad ? 110 : 150, screenR = bodyR - bezel
    hex(0x2A2A2E).setFill()  // side buttons
    if iPad {
        NSBezierPath(roundedRect: NSRect(x: body.maxX - 260, y: body.minY - 10, width: 150, height: 16), xRadius: 8, yRadius: 8).fill()
    } else {
        NSBezierPath(roundedRect: NSRect(x: body.maxX - 6, y: body.minY + 400, width: 14, height: 190), xRadius: 6, yRadius: 6).fill()
        for (yy, hh) in [(CGFloat(300), CGFloat(90)), (430, 150), (610, 150)] {
            NSBezierPath(roundedRect: NSRect(x: body.minX - 8, y: body.minY + yy, width: 14, height: hh), xRadius: 6, yRadius: 6).fill()
        }
    }
    hex(0x111114).setFill()
    NSBezierPath(roundedRect: body, xRadius: bodyR, yRadius: bodyR).fill()
    hex(0x3A3A40).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: bodyR - 3, yRadius: bodyR - 3); rim.lineWidth = 4; rim.stroke()
    let screen = body.insetBy(dx: bezel, dy: bezel)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screen, xRadius: screenR, yRadius: screenR).addClip()
    shot.draw(in: screen, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    NSGraphicsContext.restoreGraphicsState()
    if !iPad {  // Dynamic Island
        let iw = screenW * 0.284, ih = screenW * 0.083
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: screen.midX - iw / 2, y: screen.minY + screenW * 0.027, width: iw, height: ih), xRadius: ih / 2, yRadius: ih / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    let url = URL(fileURLWithPath: "\(out)/\(i + 1)-\(iPad ? "ipad13" : "iphone").png") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, cg.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

try! FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for i in slides.indices { render(i) }
