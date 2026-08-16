// pdfmerge — concatenate PDFs (and stray image attachments) into one file.
// usage: pdfmerge <out.pdf> <in1> <in2> ...

import Foundation
import PDFKit
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: pdfmerge <out.pdf> <in...>\n".data(using: .utf8)!)
    exit(2)
}
let outPath = args[1]
let output = PDFDocument()
var page = 0

for path in args.dropFirst(2) {
    let url = URL(fileURLWithPath: path)
    if let doc = PDFDocument(url: url) {
        for i in 0..<doc.pageCount {
            if let p = doc.page(at: i) { output.insert(p, at: page); page += 1 }
        }
    } else if let img = NSImage(contentsOf: url), let p = PDFPage(image: img) {
        output.insert(p, at: page); page += 1
    } else {
        FileHandle.standardError.write("skipped (unreadable): \(path)\n".data(using: .utf8)!)
    }
}

guard page > 0, output.write(toFile: outPath) else {
    FileHandle.standardError.write("nothing written for \(outPath)\n".data(using: .utf8)!)
    exit(1)
}
