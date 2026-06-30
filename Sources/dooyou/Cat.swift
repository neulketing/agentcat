import Cocoa

let dooyouFrames = [0, 1, 2, 3]

private let dooyouFrameImages: [NSImage] = loadDooyouFrameImages()

private func loadDooyouFrameImages() -> [NSImage] {
    dooyouFrames.compactMap { frame in
        for url in candidateResourceURLs(named: "dooyou-run-\(frame)", extension: "png") {
            if let image = NSImage(contentsOf: url) {
                image.isTemplate = false
                return image
            }
        }
        return nil
    }
}

private func candidateResourceURLs(named name: String, extension ext: String) -> [URL] {
    let bundleNames = ["dooyou_dooyou.bundle", "agentcat_agentcat.bundle"]
    let appBases = [
        Bundle.main.resourceURL,
        Optional(Bundle.main.bundleURL),
        Bundle.main.executableURL?.deletingLastPathComponent(),
    ].compactMap { $0 }
    var urls: [URL] = []
    for base in appBases {
        urls.append(base.appendingPathComponent("\(name).\(ext)"))
        for bundleName in bundleNames {
            urls.append(base.appendingPathComponent(bundleName).appendingPathComponent("\(name).\(ext)"))
        }
    }
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Resources")
        .appendingPathComponent("\(name).\(ext)")
    urls.append(sourceURL)
    return urls
}

func dooyouImage(_ frame: Int, height: CGFloat = 18, isSprinting: Bool = false, mascot: MascotID = .coton, background: BackgroundThemeID = .automatic) -> NSImage {
    guard mascot == .coton, !dooyouFrameImages.isEmpty else {
        return fallbackDooyouImage(frame, height: height, isSprinting: isSprinting, mascot: mascot, background: background)
    }

    let sprite = dooyouFrameImages[frame % dooyouFrameImages.count]
    let canvasWidth = background == .automatic ? height * 1.72 : height * 2.28
    let renderHeight = max(1, height - 2)
    let aspect = sprite.size.width / max(sprite.size.height, 1)
    var drawWidth = renderHeight * aspect
    var drawHeight = renderHeight
    if drawWidth > canvasWidth {
        drawWidth = canvasWidth
        drawHeight = canvasWidth / max(aspect, 1)
    }
    let image = NSImage(size: NSSize(width: canvasWidth, height: height))

    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    drawMenuBackground(theme: background, height: height, width: canvasWidth)
    sprite.draw(
        in: NSRect(
            x: (canvasWidth - drawWidth) / 2,
            y: (height - drawHeight) / 2,
            width: drawWidth,
            height: drawHeight
        ),
        from: NSRect(origin: .zero, size: sprite.size),
        operation: .sourceOver,
        fraction: 1
    )
    if isSprinting {
        drawSweat(frame: frame, height: height, canvasWidth: canvasWidth)
    }
    image.unlockFocus()
    image.isTemplate = false
    return image
}

private func drawMenuBackground(theme: BackgroundThemeID, height: CGFloat, width: CGFloat) {
    let rect = NSRect(x: 0.8, y: 0.8, width: width - 1.6, height: height - 1.6)
    let path = NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)
    let colors = menuBackgroundColors(theme)
    let gradient = NSGradient(starting: colors.0, ending: colors.1)
    gradient?.draw(in: path, angle: 0)
    colors.2.setStroke()
    path.lineWidth = 0.8
    path.stroke()
}

private func menuBackgroundColors(_ theme: BackgroundThemeID) -> (NSColor, NSColor, NSColor) {
    switch theme {
    case .automatic:
        return (
            NSColor.white.withAlphaComponent(0.26),
            NSColor.white.withAlphaComponent(0.10),
            NSColor.white.withAlphaComponent(0.30)
        )
    case .room:
        return (
            NSColor(red: 1.0, green: 0.82, blue: 0.62, alpha: 0.95),
            NSColor(red: 1.0, green: 0.55, blue: 0.36, alpha: 0.90),
            NSColor(red: 0.85, green: 0.36, blue: 0.22, alpha: 0.75)
        )
    case .forest, .park:
        return (
            NSColor(red: 0.64, green: 0.88, blue: 0.56, alpha: 0.92),
            NSColor(red: 0.18, green: 0.64, blue: 0.38, alpha: 0.88),
            NSColor(red: 0.10, green: 0.42, blue: 0.24, alpha: 0.72)
        )
    case .playground:
        return (
            NSColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 0.92),
            NSColor(red: 0.95, green: 0.28, blue: 0.34, alpha: 0.88),
            NSColor(red: 0.70, green: 0.18, blue: 0.28, alpha: 0.72)
        )
    case .space:
        return (
            NSColor(red: 0.13, green: 0.15, blue: 0.22, alpha: 0.94),
            NSColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 0.92),
            NSColor(red: 0.55, green: 0.62, blue: 0.78, alpha: 0.60)
        )
    }
}

private func drawSweat(frame: Int, height: CGFloat, canvasWidth: CGFloat) {
    let phase = frame % max(dooyouFrames.count, 1)
    let drops: [(CGFloat, CGFloat, CGFloat)] = [
        (canvasWidth - 4.0 - CGFloat(phase % 2), height - 4.0, 1.45),
        (canvasWidth - 8.5 - CGFloat((phase + 1) % 2), height - 7.0, 1.05),
    ]
    NSColor(red: 0.30, green: 0.74, blue: 1.0, alpha: 0.88).setFill()
    NSColor.white.withAlphaComponent(0.8).setStroke()
    for (x, y, size) in drops {
        let drop = NSBezierPath()
        drop.move(to: NSPoint(x: x, y: y + size))
        drop.curve(to: NSPoint(x: x - size, y: y - size * 0.15),
                   controlPoint1: NSPoint(x: x - size * 0.9, y: y + size * 0.35),
                   controlPoint2: NSPoint(x: x - size * 1.0, y: y + size * 0.05))
        drop.curve(to: NSPoint(x: x, y: y - size),
                   controlPoint1: NSPoint(x: x - size * 0.75, y: y - size * 0.75),
                   controlPoint2: NSPoint(x: x - size * 0.25, y: y - size))
        drop.curve(to: NSPoint(x: x + size, y: y - size * 0.15),
                   controlPoint1: NSPoint(x: x + size * 0.25, y: y - size),
                   controlPoint2: NSPoint(x: x + size * 0.75, y: y - size * 0.75))
        drop.curve(to: NSPoint(x: x, y: y + size),
                   controlPoint1: NSPoint(x: x + size * 1.0, y: y + size * 0.05),
                   controlPoint2: NSPoint(x: x + size * 0.9, y: y + size * 0.35))
        drop.close()
        drop.fill()
        drop.lineWidth = 0.45
        drop.stroke()
    }
}

private struct MascotPalette {
    let body: NSColor
    let stroke: NSColor
    let accent: NSColor
}

private func palette(for mascot: MascotID) -> MascotPalette {
    switch mascot {
    case .coton: return MascotPalette(body: NSColor(red: 0.96, green: 0.63, blue: 0.28, alpha: 1), stroke: NSColor(red: 0.38, green: 0.20, blue: 0.10, alpha: 1), accent: NSColor(red: 1.0, green: 0.83, blue: 0.45, alpha: 1))
    case .cat: return MascotPalette(body: NSColor(red: 0.95, green: 0.62, blue: 0.28, alpha: 1), stroke: NSColor(red: 0.38, green: 0.20, blue: 0.10, alpha: 1), accent: NSColor(red: 1.0, green: 0.86, blue: 0.56, alpha: 1))
    case .turtle: return MascotPalette(body: NSColor(red: 0.36, green: 0.64, blue: 0.36, alpha: 1), stroke: NSColor(red: 0.15, green: 0.34, blue: 0.18, alpha: 1), accent: NSColor(red: 0.62, green: 0.48, blue: 0.27, alpha: 1))
    case .whiteDog: return MascotPalette(body: NSColor(red: 0.98, green: 0.98, blue: 0.95, alpha: 1), stroke: NSColor(red: 0.36, green: 0.36, blue: 0.36, alpha: 1), accent: NSColor(red: 0.86, green: 0.90, blue: 0.95, alpha: 1))
    case .blackDog: return MascotPalette(body: NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1), stroke: NSColor(red: 0.88, green: 0.86, blue: 0.78, alpha: 1), accent: NSColor(red: 0.28, green: 0.29, blue: 0.32, alpha: 1))
    case .fox: return MascotPalette(body: NSColor(red: 0.92, green: 0.42, blue: 0.15, alpha: 1), stroke: NSColor(red: 0.38, green: 0.16, blue: 0.06, alpha: 1), accent: NSColor.white)
    case .hamster: return MascotPalette(body: NSColor(red: 0.88, green: 0.70, blue: 0.50, alpha: 1), stroke: NSColor(red: 0.40, green: 0.27, blue: 0.16, alpha: 1), accent: NSColor(red: 1.0, green: 0.86, blue: 0.67, alpha: 1))
    case .penguin: return MascotPalette(body: NSColor(red: 0.13, green: 0.17, blue: 0.22, alpha: 1), stroke: NSColor(red: 0.85, green: 0.88, blue: 0.90, alpha: 1), accent: NSColor.white)
    case .dragon: return MascotPalette(body: NSColor(red: 0.13, green: 0.68, blue: 0.38, alpha: 1), stroke: NSColor(red: 0.05, green: 0.31, blue: 0.17, alpha: 1), accent: NSColor(red: 0.72, green: 0.94, blue: 0.55, alpha: 1))
    case .slime: return MascotPalette(body: NSColor(red: 0.36, green: 0.82, blue: 0.30, alpha: 1), stroke: NSColor(red: 0.13, green: 0.43, blue: 0.12, alpha: 1), accent: NSColor(red: 0.72, green: 1.0, blue: 0.64, alpha: 1))
    case .robot: return MascotPalette(body: NSColor(red: 0.72, green: 0.76, blue: 0.80, alpha: 1), stroke: NSColor(red: 0.20, green: 0.24, blue: 0.28, alpha: 1), accent: NSColor(red: 0.30, green: 0.74, blue: 1.0, alpha: 1))
    case .otter: return MascotPalette(body: NSColor(red: 0.40, green: 0.27, blue: 0.18, alpha: 1), stroke: NSColor(red: 0.22, green: 0.14, blue: 0.09, alpha: 1), accent: NSColor(red: 0.78, green: 0.61, blue: 0.43, alpha: 1))
    case .horse: return MascotPalette(body: NSColor(red: 0.62, green: 0.30, blue: 0.16, alpha: 1), stroke: NSColor(red: 0.30, green: 0.14, blue: 0.08, alpha: 1), accent: NSColor(red: 0.92, green: 0.70, blue: 0.45, alpha: 1))
    }
}

private func fallbackDooyouImage(_ frame: Int, height: CGFloat, isSprinting: Bool, mascot: MascotID, background: BackgroundThemeID) -> NSImage {
    let width = background == .automatic ? height * 1.72 : height * 2.28
    let image = NSImage(size: NSSize(width: width, height: height))
    let phase = frame % max(dooyouFrames.count, 1)
    let hop = [0.0, 0.45, 0.0, -0.25][phase] * height / 18
    let colors = palette(for: mascot)

    image.lockFocus()
    NSGraphicsContext.current?.shouldAntialias = true
    drawMenuBackground(theme: background, height: height, width: width)
    switch mascot {
    case .cat:
        drawCatMascot(height: height, width: width, hop: hop, phase: phase, colors: colors)
    case .turtle:
        drawTurtleMascot(height: height, width: width, hop: hop, phase: phase, colors: colors)
    default:
        drawCapsuleMascot(height: height, width: width, hop: hop, colors: colors)
    }
    if isSprinting {
        drawSweat(frame: frame, height: height, canvasWidth: width)
    }

    image.unlockFocus()
    image.isTemplate = false
    return image
}

private func drawCapsuleMascot(height: CGFloat, width: CGFloat, hop: CGFloat, colors: MascotPalette) {
    let bodyWidth = height * 1.16
    let bodyX = (width - bodyWidth) / 2 - 1
    let body = NSBezierPath(roundedRect: NSRect(x: bodyX, y: 3 + hop, width: bodyWidth, height: height - 7), xRadius: 7, yRadius: 7)
    colors.body.setFill()
    body.fill()
    colors.stroke.setStroke()
    body.lineWidth = 0.9
    body.stroke()

    let head = NSBezierPath(ovalIn: NSRect(x: bodyX + bodyWidth - 7, y: 6 + hop, width: 8, height: 8))
    colors.body.setFill()
    head.fill()
    head.stroke()

    let accent = NSBezierPath(ovalIn: NSRect(x: bodyX + 3, y: 7 + hop, width: 4.2, height: 3.5))
    colors.accent.withAlphaComponent(0.85).setFill()
    accent.fill()

    NSColor.black.setFill()
    NSBezierPath(ovalIn: NSRect(x: bodyX + bodyWidth - 1.5, y: 9 + hop, width: 1.8, height: 1.5)).fill()
}

private func drawCatMascot(height: CGFloat, width: CGFloat, hop: CGFloat, phase: Int, colors: MascotPalette) {
    let bodyRect = NSRect(x: width * 0.26, y: height * 0.25 + hop, width: height * 0.78, height: height * 0.46)
    let headRect = NSRect(x: bodyRect.maxX - height * 0.16, y: height * 0.40 + hop, width: height * 0.43, height: height * 0.43)
    let tailLift = CGFloat([0.00, 0.04, 0.00, -0.03][phase]) * height
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: bodyRect.minX + height * 0.06, y: bodyRect.midY + height * 0.03))
    tail.curve(to: NSPoint(x: bodyRect.minX - height * 0.18, y: bodyRect.midY + height * 0.28 + tailLift),
               controlPoint1: NSPoint(x: bodyRect.minX - height * 0.12, y: bodyRect.midY + height * 0.02),
               controlPoint2: NSPoint(x: bodyRect.minX - height * 0.22, y: bodyRect.midY + height * 0.14 + tailLift))
    colors.body.setStroke()
    tail.lineWidth = max(1.5, height * 0.10)
    tail.lineCapStyle = .round
    tail.stroke()

    colors.body.setFill()
    colors.stroke.setStroke()
    let body = NSBezierPath(ovalIn: bodyRect)
    body.fill()
    body.lineWidth = 0.85
    body.stroke()

    let head = NSBezierPath(ovalIn: headRect)
    head.fill()
    head.stroke()

    let leftEar = NSBezierPath()
    leftEar.move(to: NSPoint(x: headRect.minX + height * 0.09, y: headRect.maxY - height * 0.03))
    leftEar.line(to: NSPoint(x: headRect.minX + height * 0.16, y: headRect.maxY + height * 0.14))
    leftEar.line(to: NSPoint(x: headRect.minX + height * 0.24, y: headRect.maxY - height * 0.02))
    leftEar.close()
    let rightEar = NSBezierPath()
    rightEar.move(to: NSPoint(x: headRect.maxX - height * 0.24, y: headRect.maxY - height * 0.02))
    rightEar.line(to: NSPoint(x: headRect.maxX - height * 0.15, y: headRect.maxY + height * 0.13))
    rightEar.line(to: NSPoint(x: headRect.maxX - height * 0.07, y: headRect.maxY - height * 0.04))
    rightEar.close()
    leftEar.fill()
    rightEar.fill()
    leftEar.stroke()
    rightEar.stroke()

    colors.accent.withAlphaComponent(0.80).setFill()
    NSBezierPath(ovalIn: NSRect(x: bodyRect.minX + height * 0.28, y: bodyRect.midY - height * 0.08, width: height * 0.18, height: height * 0.13)).fill()

    colors.stroke.withAlphaComponent(0.45).setStroke()
    for x in [bodyRect.minX + height * 0.20, bodyRect.minX + height * 0.34, bodyRect.minX + height * 0.48] {
        let stripe = NSBezierPath()
        stripe.move(to: NSPoint(x: x, y: bodyRect.maxY - height * 0.06))
        stripe.line(to: NSPoint(x: x + height * 0.05, y: bodyRect.midY + height * 0.01))
        stripe.lineWidth = 0.55
        stripe.stroke()
    }

    colors.stroke.setStroke()
    for x in [bodyRect.minX + height * 0.18, bodyRect.midX + height * 0.05, bodyRect.maxX - height * 0.10] {
        let leg = NSBezierPath()
        leg.move(to: NSPoint(x: x, y: bodyRect.minY + height * 0.03))
        leg.line(to: NSPoint(x: x + height * 0.07, y: bodyRect.minY - height * 0.07))
        leg.lineWidth = 0.9
        leg.stroke()
    }

    NSColor.black.setFill()
    NSBezierPath(ovalIn: NSRect(x: headRect.maxX - height * 0.14, y: headRect.midY + height * 0.03, width: height * 0.06, height: height * 0.05)).fill()
}

private func drawTurtleMascot(height: CGFloat, width: CGFloat, hop: CGFloat, phase: Int, colors: MascotPalette) {
    let crawl = CGFloat([0.00, 0.03, 0.00, -0.02][phase]) * height
    let shellRect = NSRect(x: width * 0.30, y: height * 0.26 + hop, width: height * 0.82, height: height * 0.50)
    let headRect = NSRect(x: shellRect.maxX - height * 0.03 + crawl, y: shellRect.midY - height * 0.12, width: height * 0.28, height: height * 0.26)

    colors.body.setFill()
    colors.stroke.setStroke()
    NSBezierPath(ovalIn: headRect).fill()
    NSBezierPath(ovalIn: headRect).stroke()

    for leg in [
        NSRect(x: shellRect.minX + height * 0.08, y: shellRect.minY - height * 0.06, width: height * 0.16, height: height * 0.13),
        NSRect(x: shellRect.maxX - height * 0.22, y: shellRect.minY - height * 0.06, width: height * 0.16, height: height * 0.13),
        NSRect(x: shellRect.minX + height * 0.10, y: shellRect.maxY - height * 0.06, width: height * 0.15, height: height * 0.12),
        NSRect(x: shellRect.maxX - height * 0.24, y: shellRect.maxY - height * 0.06, width: height * 0.15, height: height * 0.12),
    ] {
        let path = NSBezierPath(ovalIn: leg)
        colors.body.setFill()
        path.fill()
        path.stroke()
    }

    let shell = NSBezierPath(ovalIn: shellRect)
    colors.accent.setFill()
    shell.fill()
    colors.stroke.setStroke()
    shell.lineWidth = 0.95
    shell.stroke()

    colors.body.withAlphaComponent(0.35).setStroke()
    let mid = NSBezierPath()
    mid.move(to: NSPoint(x: shellRect.midX, y: shellRect.minY + height * 0.05))
    mid.line(to: NSPoint(x: shellRect.midX, y: shellRect.maxY - height * 0.05))
    mid.lineWidth = 0.7
    mid.stroke()

    for offset in [-0.18, 0.18] {
        let stripe = NSBezierPath()
        stripe.move(to: NSPoint(x: shellRect.midX + height * offset, y: shellRect.minY + height * 0.08))
        stripe.curve(to: NSPoint(x: shellRect.midX + height * offset, y: shellRect.maxY - height * 0.08),
                     controlPoint1: NSPoint(x: shellRect.midX + height * (offset - 0.08), y: shellRect.midY - height * 0.08),
                     controlPoint2: NSPoint(x: shellRect.midX + height * (offset + 0.08), y: shellRect.midY + height * 0.08))
        stripe.lineWidth = 0.55
        stripe.stroke()
    }

    NSColor.black.setFill()
    NSBezierPath(ovalIn: NSRect(x: headRect.maxX - height * 0.09, y: headRect.midY + height * 0.03, width: height * 0.045, height: height * 0.04)).fill()
}
