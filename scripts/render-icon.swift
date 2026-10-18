import AppKit
import CoreGraphics
import Foundation

// Renders the Open OBD GUI app icon at 1024 x 1024: graphite squircle, rev counter arc with red zone, needle, OBD socket.
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Squircle on the macOS icon grid: 824 points with a 100 point margin.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(shape)
ctx.setFillColor(color(0x0B0F14))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let background = CGGradient(colorsSpace: space, colors: [color(0x26303D), color(0x10151C), color(0x07090C)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
let glow = CGGradient(colorsSpace: space, colors: [color(0x0A84FF, 0.28), color(0x0A84FF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0, endCenter: CGPoint(x: 512, y: 560), endRadius: 420, options: [])
ctx.restoreGState()

// Thin top highlight along the edge.
ctx.saveGState()
ctx.addPath(shape)
ctx.setStrokeColor(color(0xFFFFFF, 0.10))
ctx.setLineWidth(4)
ctx.strokePath()
ctx.restoreGState()

let center = CGPoint(x: 512, y: 548)
let radius: CGFloat = 268
func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }
// 270 degree sweep, opening at the bottom: from 225 degrees clockwise to -45 degrees.
let start: CGFloat = 225
let sweep: CGFloat = 270
func angle(_ fraction: CGFloat) -> CGFloat { start - sweep * fraction }
func arc(_ from: CGFloat, _ to: CGFloat, width: CGFloat, _ stroke: CGColor, cap: CGLineCap = .round) {
    ctx.saveGState()
    ctx.addArc(center: center, radius: radius, startAngle: radians(angle(from)), endAngle: radians(angle(to)), clockwise: true)
    ctx.setStrokeColor(stroke)
    ctx.setLineWidth(width)
    ctx.setLineCap(cap)
    ctx.strokePath()
    ctx.restoreGState()
}

arc(0, 1, width: 40, color(0xFFFFFF, 0.10))
arc(0.82, 1, width: 40, color(0xFF453A, 0.95))
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 30, color: color(0x0A84FF, 0.9))
arc(0, 0.64, width: 40, color(0x0A84FF))
ctx.restoreGState()

// Ticks inside the arc.
for index in 0...10 {
    let fraction = CGFloat(index) / 10
    let theta = radians(angle(fraction))
    let major = index % 2 == 0
    let outer = radius - 44
    let inner = outer - (major ? 46 : 26)
    ctx.move(to: CGPoint(x: center.x + cos(theta) * inner, y: center.y + sin(theta) * inner))
    ctx.addLine(to: CGPoint(x: center.x + cos(theta) * outer, y: center.y + sin(theta) * outer))
    ctx.setStrokeColor(fraction >= 0.8 ? color(0xFF453A, 0.9) : color(0xFFFFFF, major ? 0.75 : 0.4))
    ctx.setLineWidth(major ? 12 : 8)
    ctx.setLineCap(.round)
    ctx.strokePath()
}

// Needle at the end of the blue arc.
let needleAngle = radians(angle(0.64))
let tip = CGPoint(x: center.x + cos(needleAngle) * (radius - 40), y: center.y + sin(needleAngle) * (radius - 40))
let normal = needleAngle + .pi / 2
let base = CGFloat(18)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0x000000, 0.5))
ctx.move(to: tip)
ctx.addLine(to: CGPoint(x: center.x + cos(normal) * base, y: center.y + sin(normal) * base))
ctx.addLine(to: CGPoint(x: center.x - cos(needleAngle) * 36, y: center.y - sin(needleAngle) * 36))
ctx.addLine(to: CGPoint(x: center.x - cos(normal) * base, y: center.y - sin(normal) * base))
ctx.closePath()
ctx.setFillColor(color(0xF5F7FA))
ctx.fillPath()
ctx.addEllipse(in: CGRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68))
ctx.setFillColor(color(0xF5F7FA))
ctx.fillPath()
ctx.restoreGState()
ctx.addEllipse(in: CGRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28))
ctx.setFillColor(color(0x10151C))
ctx.fillPath()

// OBD socket in the opening of the arc: trapezoid with two rows of eight pins.
let socketTop: CGFloat = 352, socketBottom: CGFloat = 248
let socket = CGMutablePath()
socket.move(to: CGPoint(x: 512 - 132, y: socketTop))
socket.addLine(to: CGPoint(x: 512 + 132, y: socketTop))
socket.addLine(to: CGPoint(x: 512 + 104, y: socketBottom))
socket.addLine(to: CGPoint(x: 512 - 104, y: socketBottom))
socket.closeSubpath()
ctx.addPath(socket)
ctx.setStrokeColor(color(0xF5F7FA, 0.92))
ctx.setLineWidth(12)
ctx.setLineJoin(.round)
ctx.strokePath()
for row in 0..<2 {
    let y = row == 0 ? CGFloat(318) : CGFloat(282)
    let half: CGFloat = row == 0 ? 96 : 80
    for pin in 0..<8 {
        let x = 512 - half + CGFloat(pin) * (2 * half / 7)
        ctx.addEllipse(in: CGRect(x: x - 8, y: y - 8, width: 16, height: 16))
    }
}
ctx.setFillColor(color(0xF5F7FA, 0.85))
ctx.fillPath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
