import AppKit
// iPhone Fare simgesi: koyu zemin, ortada fare gibi duran bir telefon (üstte iki düğme), altında hareket izi. 1024x1024 PNG.
let s = 1024
let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a) }
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)); ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [rgb(0x24324F), rgb(0x0B1020)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// Hareket izi: telefonun arkasında kesik kesik sarı çizgi
ctx.setStrokeColor(rgb(0xFBBF24, 0.9)); ctx.setLineWidth(22); ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [2, 52])
ctx.move(to: CGPoint(x: 230, y: 250)); ctx.addCurve(to: CGPoint(x: 470, y: 420), control1: CGPoint(x: 300, y: 420), control2: CGPoint(x: 380, y: 300)); ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])
// Telefon
let tel = CGRect(x: 400, y: 230, width: 300, height: 560)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(0x000000, 0.6))
ctx.addPath(CGPath(roundedRect: tel, cornerWidth: 62, cornerHeight: 62, transform: nil)); ctx.setFillColor(rgb(0xE9EDF3)); ctx.fillPath()
ctx.restoreGState()
let ekran = tel.insetBy(dx: 20, dy: 20)
ctx.addPath(CGPath(roundedRect: ekran, cornerWidth: 44, cornerHeight: 44, transform: nil)); ctx.setFillColor(rgb(0x111827)); ctx.fillPath()
// Ekranın üstünde iki fare düğmesi ve kaydırma şeridi
let ust = CGRect(x: ekran.minX + 18, y: ekran.maxY - 230, width: ekran.width - 36, height: 210)
let yarim = (ust.width - 50) / 2
ctx.setFillColor(rgb(0x60A5FA))
ctx.addPath(CGPath(roundedRect: CGRect(x: ust.minX, y: ust.minY, width: yarim, height: ust.height), cornerWidth: 30, cornerHeight: 30, transform: nil)); ctx.fillPath()
ctx.setFillColor(rgb(0x374151))
ctx.addPath(CGPath(roundedRect: CGRect(x: ust.maxX - yarim, y: ust.minY, width: yarim, height: ust.height), cornerWidth: 30, cornerHeight: 30, transform: nil)); ctx.fillPath()
ctx.setFillColor(rgb(0x9CA3AF))
ctx.addPath(CGPath(roundedRect: CGRect(x: ust.midX - 12, y: ust.minY + 40, width: 24, height: ust.height - 80), cornerWidth: 12, cornerHeight: 12, transform: nil)); ctx.fillPath()
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
