// render — turn each extracted Notes HTML body into a single tall PDF page.
// Pagination into Letter pages is left to `paginate`, so both the fast path and
// the Notes-export path go through identical slicing logic.
//
// usage: render <jobs.tsv>      # each line: <htmlPath> \t <outPdfPath>

import Cocoa
import WebKit

let contentWidth: CGFloat = 900

struct Job { let html: String; let out: String }

guard CommandLine.arguments.count == 2,
      let text = try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8) else {
    FileHandle.standardError.write("usage: render <jobs.tsv>\n".data(using: .utf8)!)
    exit(2)
}

let jobs: [Job] = text.split(separator: "\n").compactMap { line in
    let f = line.components(separatedBy: "\t")
    guard f.count >= 2 else { return nil }
    return Job(html: f[0], out: f[1])
}

// Notes' inline images carry `max-height:100%`, which collapses them to nothing
// once the page is unbounded in height. Override that and let them span the width.
let css = """
<style>
  html,body { margin:0; padding:20px; background:#fff;
              font:13px -apple-system,'Helvetica Neue',sans-serif; color:#000;
              -webkit-text-size-adjust:100%; }
  img { max-width:100% !important; max-height:none !important;
        width:auto !important; height:auto !important; display:block; }
  table { border-collapse:collapse; }
  * { overflow-wrap:anywhere; }
</style>
"""

final class Driver: NSObject, WKNavigationDelegate {
    let web: WKWebView
    let window: NSWindow
    var index = 0
    var failures: [String] = []

    override init() {
        let cfg = WKWebViewConfiguration()
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: contentWidth, height: 1200),
                        configuration: cfg)
        // WebKit needs the view in a window to lay out and paint reliably.
        window = NSWindow(contentRect: web.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.contentView = web
        window.setIsVisible(false)
        super.init()
        web.navigationDelegate = self
    }

    func start() { next() }

    func next() {
        guard index < jobs.count else {
            if !failures.isEmpty {
                FileHandle.standardError.write(
                    ("failed: " + failures.joined(separator: ", ") + "\n").data(using: .utf8)!)
            }
            print("rendered \(jobs.count - failures.count)/\(jobs.count)")
            exit(failures.isEmpty ? 0 : 1)
        }
        let job = jobs[index]
        guard let body = try? String(contentsOfFile: job.html, encoding: .utf8) else {
            failures.append(job.html); index += 1; next(); return
        }
        web.loadHTMLString(css + body, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // give layout + image decode a moment to settle before measuring
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.capture() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError e: Error) {
        failures.append(jobs[index].html); index += 1; next()
    }

    func capture() {
        web.evaluateJavaScript("document.body.scrollHeight") { [self] result, _ in
            let h = max(200, CGFloat((result as? NSNumber)?.doubleValue ?? 1200))
            web.frame = CGRect(x: 0, y: 0, width: contentWidth, height: h)
            window.setContentSize(NSSize(width: contentWidth, height: h))

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let cfg = WKPDFConfiguration()
                cfg.rect = CGRect(x: 0, y: 0, width: contentWidth, height: h)
                web.createPDF(configuration: cfg) { [self] res in
                    switch res {
                    case .success(let data):
                        try? data.write(to: URL(fileURLWithPath: jobs[index].out))
                    case .failure:
                        failures.append(jobs[index].html)
                    }
                    index += 1
                    if index % 25 == 0 { print("  \(index)/\(jobs.count)") }
                    next()
                }
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let driver = Driver()
DispatchQueue.main.async { driver.start() }
app.run()
