#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: generate-app-icon.swift /absolute/output.png\n".utf8))
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard outputURL.path.hasPrefix("/") else {
    FileHandle.standardError.write(Data("error: output path must be absolute\n".utf8))
    exit(64)
}

let canvas = 1_024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil,
    width: canvas,
    height: canvas,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Unable to create icon canvas")
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: colorSpace,
        components: [
            CGFloat((hex >> 16) & 0xff) / 255,
            CGFloat((hex >> 8) & 0xff) / 255,
            CGFloat(hex & 0xff) / 255,
            alpha
        ]
    )!
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawTrack(_ path: CGPath, fill: CGColor, highlight: CGColor) {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 22, color: color(0x101318, alpha: 0.28))
    context.addPath(path)
    context.setStrokeColor(fill)
    context.setLineWidth(132)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
    context.restoreGState()

    context.saveGState()
    context.addPath(path)
    context.setStrokeColor(highlight)
    context.setLineWidth(5)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
    context.restoreGState()
}

context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

let shellRect = CGRect(x: 88, y: 88, width: 848, height: 848)
let shellPath = roundedRect(shellRect, radius: 208)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -22), blur: 40, color: color(0x101318, alpha: 0.24))
context.addPath(shellPath)
context.setFillColor(color(0xF7F8FA))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(shellPath)
context.clip()
let shellGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [color(0xFFFFFF), color(0xE7E9ED)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    shellGradient,
    start: CGPoint(x: 512, y: 900),
    end: CGPoint(x: 512, y: 120),
    options: []
)
context.restoreGState()

context.addPath(shellPath)
context.setStrokeColor(color(0xCDD2D9))
context.setLineWidth(10)
context.strokePath()

let upper = CGMutablePath()
upper.move(to: CGPoint(x: 492, y: 512))
upper.addCurve(
    to: CGPoint(x: 370, y: 340),
    control1: CGPoint(x: 320, y: 512),
    control2: CGPoint(x: 250, y: 476)
)
upper.addLine(to: CGPoint(x: 675, y: 340))

let lower = CGMutablePath()
lower.move(to: CGPoint(x: 532, y: 512))
lower.addCurve(
    to: CGPoint(x: 654, y: 684),
    control1: CGPoint(x: 704, y: 512),
    control2: CGPoint(x: 774, y: 548)
)
lower.addLine(to: CGPoint(x: 349, y: 684))

drawTrack(lower, fill: color(0x20242A), highlight: color(0x515862, alpha: 0.72))
drawTrack(upper, fill: color(0x3267E3), highlight: color(0x7298F2, alpha: 0.78))

let upperArrow = CGMutablePath()
upperArrow.move(to: CGPoint(x: 630, y: 225))
upperArrow.addLine(to: CGPoint(x: 842, y: 340))
upperArrow.addLine(to: CGPoint(x: 630, y: 455))
upperArrow.closeSubpath()
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: color(0x101318, alpha: 0.28))
context.addPath(upperArrow)
context.setFillColor(color(0x3267E3))
context.fillPath()
context.restoreGState()

let lowerArrow = CGMutablePath()
lowerArrow.move(to: CGPoint(x: 394, y: 569))
lowerArrow.addLine(to: CGPoint(x: 182, y: 684))
lowerArrow.addLine(to: CGPoint(x: 394, y: 799))
lowerArrow.closeSubpath()
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: color(0x101318, alpha: 0.28))
context.addPath(lowerArrow)
context.setFillColor(color(0x20242A))
context.fillPath()
context.restoreGState()

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: color(0x101318, alpha: 0.32))
context.setFillColor(color(0xF7F8FA))
context.fillEllipse(in: CGRect(x: 444, y: 444, width: 136, height: 136))
context.restoreGState()
context.setFillColor(color(0xE99A2E))
context.fillEllipse(in: CGRect(x: 462, y: 462, width: 100, height: 100))
context.setStrokeColor(color(0xB96B10))
context.setLineWidth(5)
context.strokeEllipse(in: CGRect(x: 462, y: 462, width: 100, height: 100))

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          outputURL as CFURL,
          UTType.png.identifier as CFString,
          1,
          nil
      ) else {
    fatalError("Unable to create icon image")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Unable to write icon image")
}

