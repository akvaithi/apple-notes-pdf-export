// audit — rasterize every page of every PDF at low resolution and report ink
// coverage, so blank or near-blank pages (the signature of content loss) surface.
//
// usage: audit <root-dir>

import Foundation
import CoreGraphics

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: audit <root>\n".data(using: .utf8)!)
    exit(2)
}
let root = CommandLine.arguments[1]

func inkFraction(_ page: CGPDFPage) -> Double? {
    let box = page.getBoxRect(.mediaBox)
    guard box.width > 1, box.height > 1 else { return nil }
    let w = 120
    let h = max(1, Int((Double(w) * box.height / box.width).rounded()))
    var buf = [UInt8](repeating: 0, count: w * h)
    guard let ctx = buf.withUnsafeMutableBytes({ raw in
        CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                  bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
    }) else { return nil }
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
    ctx.scaleBy(x: CGFloat(w) / box.width, y: CGFloat(h) / box.height)
    ctx.translateBy(x: -box.minX, y: -box.minY)
    ctx.drawPDFPage(page)
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var ink = 0
    for i in 0..<(w * h) where p[i] < 245 { ink += 1 }
    return Double(ink) / Double(w * h)
}

let fm = FileManager.default
var files: [String] = []
if let e = fm.enumerator(atPath: root) {
    for case let f as String in e where f.hasSuffix(".pdf") {
        files.append((root as NSString).appendingPathComponent(f))
    }
}
files.sort()

var totalPages = 0, blankPages = 0, emptyDocs = 0
var flagged: [String] = []

for f in files {
    guard let doc = CGPDFDocument(URL(fileURLWithPath: f) as CFURL) else {
        flagged.append("UNREADABLE  \(f)"); continue
    }
    var docInk = 0.0
    var blanks: [Int] = []
    for i in 1...max(1, doc.numberOfPages) {
        guard let pg = doc.page(at: i), let frac = inkFraction(pg) else { continue }
        totalPages += 1
        docInk += frac
        if frac < 0.002 { blankPages += 1; blanks.append(i) }
    }
    if docInk < 0.002 {
        emptyDocs += 1
        flagged.append(String(format: "EMPTY DOC   ink=%.5f  %@", docInk,
                              (f as NSString).lastPathComponent))
    } else if !blanks.isEmpty {
        flagged.append("blank pages \(blanks) in \((f as NSString).lastPathComponent)")
    }
}

print("documents: \(files.count)   pages: \(totalPages)")
print("blank pages: \(blankPages)   effectively-empty documents: \(emptyDocs)")
if !flagged.isEmpty {
    print("\nflagged:")
    for f in flagged.prefix(40) { print("  \(f)") }
    if flagged.count > 40 { print("  … \(flagged.count - 40) more") }
}
