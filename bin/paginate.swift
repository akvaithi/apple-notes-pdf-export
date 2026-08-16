// paginate — re-lay-out a PDF whose content sits in a tiny column (Notes' own
// "Export To > PDF" does this for long handwritten notes) or a single very tall
// page (WKWebView's full-content capture) into readable US Letter pages.
//
// It never rasterizes the content: each output page draws the *source* page
// under a clip + magnifying transform, so embedded images keep their native
// resolution.
//
// usage: paginate <in.pdf> <out.pdf>

import Foundation
import CoreGraphics

let pageW: CGFloat = 612, pageH: CGFloat = 792
let margin: CGFloat = 36
let usableW = pageW - margin * 2
let usableH = pageH - margin * 2
let overlap: CGFloat = 12          // shared band between slices, so nothing is cut mid-line
let maxScale: CGFloat = 14         // don't blow tiny content up past this
let minScale: CGFloat = 0.05

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write("usage: paginate <in.pdf> <out.pdf>\n".data(using: .utf8)!)
    exit(2)
}
let inURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let doc = CGPDFDocument(inURL as CFURL), doc.numberOfPages > 0 else {
    FileHandle.standardError.write("cannot open \(inURL.path)\n".data(using: .utf8)!)
    exit(1)
}

/// Find the bounding box of non-white content, in PDF points.
func contentBox(of page: CGPDFPage) -> CGRect? {
    let box = page.getBoxRect(.mediaBox)
    guard box.width > 1, box.height > 1 else { return nil }

    let rw = 240
    let rh = max(1, Int((CGFloat(rw) * box.height / box.width).rounded()))
    var buf = [UInt8](repeating: 0, count: rw * rh)

    guard let bmp = buf.withUnsafeMutableBytes({ raw -> CGContext? in
        CGContext(data: raw.baseAddress, width: rw, height: rh,
                  bitsPerComponent: 8, bytesPerRow: rw,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
    }) else { return nil }

    bmp.setFillColor(gray: 1, alpha: 1)
    bmp.fill(CGRect(x: 0, y: 0, width: CGFloat(rw), height: CGFloat(rh)))
    bmp.scaleBy(x: CGFloat(rw) / box.width, y: CGFloat(rh) / box.height)
    bmp.translateBy(x: -box.minX, y: -box.minY)
    bmp.drawPDFPage(page)

    buf = Array(UnsafeBufferPointer(start: bmp.data!.assumingMemoryBound(to: UInt8.self),
                                    count: rw * rh))

    var minC = rw, maxC = -1, minR = rh, maxR = -1
    for r in 0..<rh {
        for c in 0..<rw where buf[r * rw + c] < 245 {
            if c < minC { minC = c }
            if c > maxC { maxC = c }
            if r < minR { minR = r }
            if r > maxR { maxR = r }
        }
    }
    guard maxC >= minC, maxR >= minR else { return nil }

    // bitmap row 0 is the TOP row; user-space y grows upward.
    let sx = box.width / CGFloat(rw), sy = box.height / CGFloat(rh)
    let pad: CGFloat = 2
    let x0 = box.minX + CGFloat(minC) * sx - pad
    let x1 = box.minX + CGFloat(maxC + 1) * sx + pad
    let yTop = box.minY + CGFloat(rh - minR) * sy + pad
    let yBot = box.minY + CGFloat(rh - maxR - 1) * sy - pad
    return CGRect(x: x0, y: yBot, width: x1 - x0, height: yTop - yBot)
        .intersection(box)
}

var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
guard let ctx = CGContext(outURL as CFURL, mediaBox: &mediaBox, nil) else {
    FileHandle.standardError.write("cannot write \(outURL.path)\n".data(using: .utf8)!)
    exit(1)
}

var emitted = 0
for i in 1...doc.numberOfPages {
    guard let page = doc.page(at: i) else { continue }
    guard let bbox = contentBox(of: page), bbox.width > 0, bbox.height > 0 else { continue }

    var scale = usableW / bbox.width
    scale = min(max(scale, minScale), maxScale)

    let scaledH = bbox.height * scale
    let step = max(usableH - overlap, usableH * 0.5)
    let slices = max(1, Int(ceil((scaledH - overlap) / step)))

    for s in 0..<slices {
        // portion of the scaled content shown on this slice, measured from its top
        let topOffset = CGFloat(s) * step
        let sliceH = min(usableH, scaledH - topOffset)
        if sliceH <= 1 { continue }

        // corresponding band in source-page coordinates
        let srcTopY = bbox.maxY - topOffset / scale
        let srcBotY = srcTopY - sliceH / scale

        ctx.beginPDFPage(nil)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: pageW, height: pageH))

        ctx.saveGState()
        let target = CGRect(x: margin, y: pageH - margin - sliceH,
                            width: usableW, height: sliceH)
        ctx.clip(to: target)
        ctx.translateBy(x: margin - bbox.minX * scale,
                        y: (pageH - margin - sliceH) - srcBotY * scale)
        ctx.scaleBy(x: scale, y: scale)
        ctx.drawPDFPage(page)
        ctx.restoreGState()

        ctx.endPDFPage()
        emitted += 1
    }
}

if emitted == 0 {   // nothing but blank pages — keep one so the file is valid
    ctx.beginPDFPage(nil)
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: pageW, height: pageH))
    ctx.endPDFPage()
}
ctx.closePDF()
print("\(emitted) pages")
