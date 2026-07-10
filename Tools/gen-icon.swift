// Generates the Rhapsode app icons (production + Dev variant).
// A rhapsode performed the epics aloud — the mark is a golden lyre whose
// strings are a voice waveform. Run:
//   swiftc -o /tmp/gen-icon Tools/gen-icon.swift && /tmp/gen-icon
// Writes Resources/AppIcon-Source.png and Resources/AppIcon-Dev-Source.png,
// then `make icon` / builds regenerate the .icns files.
import AppKit

let canvas: CGFloat = 1024

func drawIcon(dev: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError() }

    // — Squircle field: deep indigo -> violet, on the macOS icon grid —
    let inset: CGFloat = 100
    let rect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
    squircle.addClip()

    let bg = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.28, alpha: 1),   // deep indigo
        NSColor(calibratedRed: 0.28, green: 0.10, blue: 0.55, alpha: 1),   // violet
        NSColor(calibratedRed: 0.42, green: 0.16, blue: 0.75, alpha: 1)    // bright violet
    ])!
    bg.draw(in: squircle, angle: -70)

    // Soft radial glow behind the lyre
    let glow = NSGradient(colors: [
        NSColor(calibratedRed: 0.98, green: 0.83, blue: 0.30, alpha: 0.22),
        NSColor.clear
    ])!
    glow.draw(fromCenter: NSPoint(x: canvas / 2, y: canvas * 0.52), radius: 60,
              toCenter: NSPoint(x: canvas / 2, y: canvas * 0.52), radius: 430, options: [])

    // — Lyre frame in gold —
    let gold = NSColor(calibratedRed: 0.97, green: 0.78, blue: 0.26, alpha: 1)
    let goldDeep = NSColor(calibratedRed: 0.85, green: 0.62, blue: 0.12, alpha: 1)
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26,
                  color: NSColor.black.withAlphaComponent(0.45).cgColor)

    let cx = canvas / 2
    let armStroke: CGFloat = 42
    let bowlY: CGFloat = 268
    let topY: CGFloat = 745
    let armSpreadTop: CGFloat = 250
    let armSpreadMid: CGFloat = 300

    func armPath(_ side: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx + side * 70, y: bowlY))
        p.curve(
            to: NSPoint(x: cx + side * armSpreadTop, y: topY),
            controlPoint1: NSPoint(x: cx + side * armSpreadMid, y: bowlY + 40),
            controlPoint2: NSPoint(x: cx + side * (armSpreadTop + 70), y: topY - 190)
        )
        p.lineWidth = armStroke
        p.lineCapStyle = .round
        return p
    }

    goldDeep.setStroke()
    for side in [CGFloat(-1), 1] {
        let shadowArm = armPath(side)
        shadowArm.lineWidth = armStroke + 10
        shadowArm.stroke()
    }
    gold.setStroke()
    armPath(-1).stroke()
    armPath(1).stroke()

    // Crossbar sits below the arm tips so the horns rise past it, classic lyre
    let crossbarY = topY - 78
    let crossbar = NSBezierPath()
    crossbar.move(to: NSPoint(x: cx - armSpreadTop - 8, y: crossbarY))
    crossbar.line(to: NSPoint(x: cx + armSpreadTop + 8, y: crossbarY))
    crossbar.lineWidth = armStroke - 6
    crossbar.lineCapStyle = .round
    gold.setStroke()
    crossbar.stroke()

    // Bowl
    let bowl = NSBezierPath()
    bowl.appendArc(withCenter: NSPoint(x: cx, y: bowlY + 26), radius: 96,
                   startAngle: 190, endAngle: 350, clockwise: false)
    bowl.lineWidth = armStroke
    bowl.lineCapStyle = .round
    bowl.stroke()

    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // — Strings as a waveform, ivory with a warm glow —
    let ivory = NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.90, alpha: 1)
    let heights: [CGFloat] = [120, 200, 300, 380, 300, 200, 120]
    let barWidth: CGFloat = 30
    let gap: CGFloat = 34
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = cx - totalWidth / 2
    let midY = (bowlY + topY) / 2
    ctx.setShadow(offset: .zero, blur: 18,
                  color: NSColor(calibratedRed: 1, green: 0.95, blue: 0.75, alpha: 0.55).cgColor)
    for h in heights {
        let bar = NSBezierPath(
            roundedRect: NSRect(x: x, y: midY - h / 2, width: barWidth, height: h),
            xRadius: barWidth / 2, yRadius: barWidth / 2
        )
        ivory.setFill()
        bar.fill()
        x += barWidth + gap
    }
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // — Dev badge: amber circle + hammer glyph, bottom-right —
    if dev {
        let badgeCenter = NSPoint(x: canvas - 250, y: 250)
        let badgeRadius: CGFloat = 118
        let badge = NSBezierPath(
            ovalIn: NSRect(x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius,
                           width: badgeRadius * 2, height: badgeRadius * 2)
        )
        NSColor(calibratedRed: 0.96, green: 0.55, blue: 0.11, alpha: 1).setFill()
        badge.fill()
        NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.28, alpha: 1).setStroke()
        badge.lineWidth = 16
        badge.stroke()

        let label = "DEV" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 74, weight: .heavy),
            .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.28, alpha: 1)
        ]
        let size = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: badgeCenter.x - size.width / 2, y: badgeCenter.y - size.height / 2),
                   withAttributes: attrs)
    }

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { fatalError("encode \(path)") }
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

writePNG(drawIcon(dev: false), to: "Resources/AppIcon-Source.png")
writePNG(drawIcon(dev: true), to: "Resources/AppIcon-Dev-Source.png")
